import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../config/business_config.dart';
import '../config/app_config.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// AI Extraction Service — powered by Groq Vision
/// Prompts are 100% generated from BusinessConfig — no hardcoded fields.
/// Works for any shop type: mobile, pharmacy, grocery, auto parts, etc.
/// ─────────────────────────────────────────────────────────────────────────────
class AiExtractionService {
  static const _endpoint = 'https://api.groq.com/openai/v1/chat/completions';

  // Vision models — tried in order, auto-fallback on 503
  static const _visionModels = [
    'meta-llama/llama-4-scout-17b-16e-instruct',
    'qwen/qwen3.6-27b',
  ];

  // Text models — tried in order, auto-fallback on 503
  static const _textModels = [
    'qwen/qwen3.6-27b',
    'llama-3.3-70b-versatile',
  ];

  // ── PUBLIC: Extract from image (vision) ─────────────────────────────────────

  /// Scan a purchase invoice image and extract structured data
  static Future<Map<String, dynamic>> extractInvoiceFromImage(
      File imageFile, BusinessConfig config) async {
    final bytes = await imageFile.readAsBytes();
    final base64Image = base64Encode(bytes);
    final prompt = _buildInvoicePrompt(config);
    return _callVision(base64Image, prompt, config, maxTokens: 2048);
  }

  /// Scan a sale slip / receipt image and extract structured data
  static Future<Map<String, dynamic>> extractSaleSlipFromImage(
      File imageFile, BusinessConfig config) async {
    final bytes = await imageFile.readAsBytes();
    final base64Image = base64Encode(bytes);
    final prompt = _buildSaleSlipPrompt(config);
    return _callVision(base64Image, prompt, config, maxTokens: 1024);
  }

  // ── PUBLIC: Extract from OCR text (text model) ──────────────────────────────

  /// Extract invoice data from raw OCR text
  static Future<Map<String, dynamic>> extractInvoiceFromText(
      String rawText, BusinessConfig config) async {
    final prompt = _buildInvoiceTextPrompt(rawText, config);
    return _callText(
      systemPrompt: _systemPrompt(config),
      userPrompt: prompt,
      maxTokens: 2048,
    );
  }

  // ── PROMPT BUILDERS ─────────────────────────────────────────────────────────

  static String _systemPrompt(BusinessConfig config) =>
      '/no_think You are an expert at reading ${config.businessType} invoices and receipts '
      'in any language and handwriting style. '
      'Always extract every visible field. Respond with valid JSON only.';

  static String _buildInvoicePrompt(BusinessConfig config) {
    final schema = _buildItemSchema(config);

    return '''
You are looking at a ${config.businessType.toUpperCase()} PURCHASE INVOICE.
${config.invoiceHint}
It may be handwritten, printed, or mixed. Any language. Read every part carefully.

Extract and return ONLY this exact JSON — no markdown, no explanation:
{
  "supplier_name": "name of the seller/supplier/shop or null",
  "invoice_number": "invoice or bill number or null",
  "invoice_date": "YYYY-MM-DD or null",
  "items": [
    $schema
  ],
  "total_amount": 0
}

RULES:
1. supplier_name: from letterhead, "From:", "Supplier:", "Seller:" — this is who SOLD to you
2. invoice_date: convert any format (DD/MM/YY, DD-MM-YYYY, written dates) to YYYY-MM-DD
3. Prices: numbers only — strip currency symbols (Rs, PKR, $, ₹, /-)
4. quantity defaults to 1 if not shown
${_identifierRules(config)}
5. If a field cannot be found, use null
''';
  }

  static String _buildSaleSlipPrompt(BusinessConfig config) {
    final itemSchema = _buildItemSaleSchema(config);

    return '''
You are looking at a ${config.businessType.toUpperCase()} SALE RECEIPT / CUSTOMER SLIP.
${config.invoiceHint}
It may be handwritten, printed, or mixed. Any language.

Extract and return ONLY this exact JSON — no markdown, no explanation:
{
  "customer_name": "customer name or null",
  "customer_phone": "customer phone number or null",
  "payment_method": "cash or card or transfer or null",
  "items": [
    $itemSaleSchema
  ],
  "total_amount": 0
}

RULES:
1. customer_name: from "Name:", "Customer:", "To:", "Buyer:" — NOT the shop name in the header
2. customer_phone: ONLY from "Mob. No:", "Mobile:", "Cell:", "Ph:" near customer details
   — any phone number in the shop header/letterhead is the SHOP's number — ignore it
3. payment_method: "cash" if nothing stated; "card"/"swipe" → "card"; "transfer"/"online"/"easypaisa"/"jazzcash" → "transfer"
4. Prices: numbers only
${_identifierRules(config)}
5. If a field cannot be found, use null
''';
  }

  static String _buildInvoiceTextPrompt(String rawText, BusinessConfig config) {
    final schema = _buildItemSchema(config);
    return '''
You are processing a ${config.businessType} PURCHASE INVOICE extracted via OCR.
${config.invoiceHint}
OCR errors are common — fix obvious mistakes.

TEXT FROM INVOICE:
$rawText

Return ONLY this exact JSON:
{
  "supplier_name": "string or null",
  "invoice_number": "string or null",
  "invoice_date": "YYYY-MM-DD or null",
  "items": [ $schema ],
  "total_amount": 0
}
''';
  }

  // ── SCHEMA BUILDERS from config fields ──────────────────────────────────────

  static String _buildItemSchema(BusinessConfig config) {
    final fields = config.productFields
        .map((f) => '      "${f.key}": "${f.label}${f.required ? " (required)" : " or null"}"')
        .join(',\n');
    return '{\n$fields,\n      "quantity": 1,\n      "unit_price": 0\n    }';
  }

  static String _buildItemSaleSchema(BusinessConfig config) {
    final fields = config.productFields
        .map((f) => '      "${f.key}": "${f.label} or null"')
        .join(',\n');
    return '{\n$fields,\n      "sale_price": 0\n    }';
  }

  static String _identifierRules(BusinessConfig config) {
    final id = config.identifierField;
    if (id == null) return '';
    return '${config.productFields.indexOf(id) + 4}. ${id.label}: '
        'unique identifier per unit — strip spaces, fix OCR character errors (0↔O, 1↔l)\n';
  }

  // ── HTTP HELPERS with retry + model fallback ─────────────────────────────────

  static Future<Map<String, dynamic>> _callVision(
    String base64Image,
    String prompt,
    BusinessConfig config, {
    int maxTokens = 1024,
  }) async {
    for (final model in _visionModels) {
      for (int attempt = 0; attempt < 2; attempt++) {
        if (attempt > 0) await Future.delayed(const Duration(seconds: 2));

        final res = await http.post(
          Uri.parse(_endpoint),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${AppConfig.groqApiKey}',
          },
          body: jsonEncode({
            'model': model,
            'messages': [
              {'role': 'system', 'content': _systemPrompt(config)},
              {
                'role': 'user',
                'content': [
                  {
                    'type': 'image_url',
                    'image_url': {'url': 'data:image/jpeg;base64,$base64Image'},
                  },
                  {'type': 'text', 'text': prompt},
                ],
              },
            ],
            'temperature': 0.1,
            'max_tokens': maxTokens,
          }),
        );

        if (res.statusCode == 200) {
          final raw =
              jsonDecode(res.body)['choices'][0]['message']['content'] as String;
          return _parseJson(raw);
        }
        if (res.statusCode != 503) {
          throw Exception('AI Vision error ($model): ${res.statusCode}');
        }
      }
    }
    throw Exception('AI is busy right now. Please try again in a moment.');
  }

  static Future<Map<String, dynamic>> _callText({
    required String systemPrompt,
    required String userPrompt,
    int maxTokens = 1024,
  }) async {
    for (final model in _textModels) {
      for (int attempt = 0; attempt < 2; attempt++) {
        if (attempt > 0) await Future.delayed(const Duration(seconds: 2));

        final res = await http.post(
          Uri.parse(_endpoint),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${AppConfig.groqApiKey}',
          },
          body: jsonEncode({
            'model': model,
            'messages': [
              {'role': 'system', 'content': systemPrompt},
              {'role': 'user', 'content': userPrompt},
            ],
            'temperature': 0.1,
            'max_tokens': maxTokens,
          }),
        );

        if (res.statusCode == 200) {
          final raw =
              jsonDecode(res.body)['choices'][0]['message']['content'] as String;
          return _parseJson(raw);
        }
        if (res.statusCode != 503) {
          throw Exception('AI error ($model): ${res.statusCode}');
        }
      }
    }
    throw Exception('AI is busy right now. Please try again in a moment.');
  }

  /// Strip Qwen think blocks + markdown fences, then parse JSON
  static Map<String, dynamic> _parseJson(String raw) {
    final clean = raw
        .replaceAll(
            RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false), '')
        .replaceAll(RegExp(r'```json\s*'), '')
        .replaceAll(RegExp(r'```\s*'), '')
        .trim();
    return jsonDecode(clean) as Map<String, dynamic>;
  }
}
