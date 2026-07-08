import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

/// Uses Groq (free, fast) for invoice/slip extraction.
/// Vision methods send the IMAGE directly — no ML Kit OCR needed.
/// Much better for handwritten text.
class GeminiService {
  static const _endpoint = 'https://api.groq.com/openai/v1/chat/completions';

  // Vision models tried in order — if primary is over capacity, falls back automatically
  static const _visionModels = [
    'meta-llama/llama-4-scout-17b-16e-instruct', // fast, reliable vision model
    'qwen/qwen3.6-27b',                           // fallback vision model
  ];

  // Text-only models tried in order
  static const _textModels = [
    'qwen/qwen3.6-27b',           // primary — best for structured extraction
    'llama-3.3-70b-versatile',    // stable production fallback
  ];

  static Future<Map<String, dynamic>> extractInvoiceData(String rawText) async {
    final prompt = '''
You are processing a mobile phone shop PURCHASE INVOICE from Pakistan or India.
The text was extracted via OCR from a HANDWRITTEN or printed invoice — OCR errors are very common.

TEXT FROM INVOICE:
$rawText

Your tasks:
1. Extract all fields below despite OCR errors and handwriting
2. Fix obvious OCR/handwriting mistakes in brand/model names:
   - "Iphsne", "Iphone" → "iPhone"; "13PM", "13 Pro Mx" → "13 Pro Max"
   - "Samsnug" → "Samsung"; "Vioo" → "Vivo"; etc.
3. Supplier name appears after: "From:", "Supplier:", "Seller:", "Shop Name:", or is the business letterhead/header
4. Invoice number appears after: "Invoice No.", "Bill No.", "Receipt No.", "#", "Inv:"
5. Date: convert to YYYY-MM-DD. Handle DD/MM/YY, DD-MM-YYYY, handwritten dates
6. IMEI: exactly 15 digits. OCR errors: 0↔O, 1↔l↔I, 8↔B
7. Prices are numbers only. "29,999", "29.999", "Rs 29999/-" → 29999
8. Storage: "128GB", "256GB", "512GB", "1TB" etc.
9. quantity defaults to 1 if not specified

Return ONLY this exact JSON, no markdown, no explanation:
{
  "supplier_name": "string or null",
  "invoice_number": "string or null",
  "invoice_date": "YYYY-MM-DD or null",
  "items": [
    {
      "brand": "string",
      "model": "string",
      "storage": "string or null",
      "color": "string or null",
      "imei": "string or null",
      "quantity": 1,
      "unit_price": 0
    }
  ],
  "total_amount": 0
}

If a field truly cannot be found, use null.
''';

    return _callText(
      systemPrompt:
          '/no_think You are an expert at reading handwritten Pakistani mobile phone shop invoices. '
          'Always extract every possible field and correct obvious OCR mistakes. '
          'Respond with valid JSON only.',
      userPrompt: prompt,
      maxTokens: 2048,
    );
  }

  /// Extract sale slip data — customer, items sold, prices, payment method
  static Future<Map<String, dynamic>> extractSaleData(String rawText) async {
    final prompt = '''
You are processing a mobile phone shop SALE SLIP from Pakistan or India.
The text was extracted via OCR from a HANDWRITTEN or printed receipt — OCR errors are very common.

TEXT FROM RECEIPT:
$rawText

Your tasks:
1. Extract all fields below despite OCR errors and handwriting
2. Fix obvious OCR/handwriting mistakes in brand/model names:
   - "Iphsne", "Iphone", "ipone" → "iPhone"
   - "13 Pro Mx", "13 PM", "13PM", "13 Pro Mox" → "13 Pro Max"
   - "Samsnug", "Samsng" → "Samsung"
   - "Vioo", "Viv0" → "Vivo"
   - Correct any garbled model name using context
3. BRAND and MODEL layout — invoices often show them on separate lines:
   "BRAND" (label) → next line has the brand value (e.g. "VIVO", "Samsung")
   "MODEL NO" or "MODEL" (label) → next line(s) have the model (e.g. "T3X 5G (6+128)", "iPhone 13 Pro Max")
   Storage/color may appear on extra lines below the model — include them in the model field.
4. Customer name appears after labels like: "Name:", "Customer Name:", "Customer:", "To:", "Buyer:", "Sold To:", "M/s:", "Purchaser:"
   - OCR often garbles handwritten names — extract best guess even if partially misread
   - Include the name even if only partially readable
5. Customer phone RULE — CRITICAL:
   - The phone number printed in the shop HEADER / LETTERHEAD (top of slip, near shop name/address like "Mob.9997848549") is the SHOP's number — DO NOT use it as customer_phone
   - The CUSTOMER's phone is only found near "Mob. No:", "Mobile:", "Cell:", "Ph:", "Contact:", "Customer Mobile:", "No.:" labels that appear in the customer details section (below the shop header)
   - Pakistan/India numbers: 10-11 digits. OCR often reads "0" as "8" — "80909 9045065893" → customer number is "9045065893"
6. IMEI: exactly 15 digits — OCR may add spaces. Remove spaces to get digits. Common errors: 0↔O, 1↔l↔I, 8↔B
7. Price/Amount: numbers only. "29,999", "29.999", "Rs 29999", "29999/-" all mean 29999
8. payment_method: if "cash" mentioned or nothing mentioned → "cash"; "card"/"swipe"/"visa" → "card"; "transfer"/"easypaisa"/"jazzcash"/"online" → "transfer"

Return ONLY this exact JSON, no markdown, no explanation:
{
  "customer_name": "string or null",
  "customer_phone": "string or null",
  "payment_method": "cash or card or transfer or null",
  "items": [
    {
      "brand": "string or null",
      "model": "string or null",
      "imei": "string or null",
      "sale_price": 0
    }
  ],
  "total_amount": 0
}

If a field truly cannot be found, use null. sale_price defaults to 0 if not found.
''';

    return _callText(
      systemPrompt:
          '/no_think You are an expert at reading handwritten Pakistani mobile phone shop receipts with OCR errors. '
          'Always extract every possible field and correct obvious OCR mistakes. '
          'Respond with valid JSON only.',
      userPrompt: prompt,
      maxTokens: 1024,
    );
  }

  // ── VISION: Send image directly — no ML Kit OCR needed ──────────────────────

  static Future<Map<String, dynamic>> extractSaleDataFromImage(File imageFile) async {
    final bytes       = await imageFile.readAsBytes();
    final base64Image = base64Encode(bytes);
    const prompt = '''
You are looking at a mobile phone shop SALE SLIP / RECEIPT from Pakistan or India.
It may be handwritten, printed, or mixed. Read every part carefully.

Extract data and return ONLY valid JSON — no markdown, no explanation:
{
  "customer_name": "string or null",
  "customer_phone": "string or null",
  "payment_method": "cash or card or transfer or null",
  "items": [
    {
      "brand": "string or null",
      "model": "string or null",
      "imei": "string or null",
      "sale_price": 0
    }
  ],
  "total_amount": 0
}

CRITICAL RULES:
1. customer_name: from "Name:", "Customer:", "To:", "Buyer:" — NOT the shop/store name in the header
2. customer_phone: from "Mob. No:", "Mobile:", "Cell:", "Ph:" near the customer name section
   — the shop phone printed in the header/top corner (like "Mob.9997848549") is the SHOP number, NOT customer phone — ignore it for customer_phone
3. brand + model: may be on separate lines below labels "BRAND" and "MODEL NO" — read those lines
4. IMEI: exactly 15 digits. Strip spaces.
5. sale_price / total_amount: numbers only, no currency symbols
6. payment_method defaults to "cash" if nothing stated
''';

    return _callVision(base64Image, prompt, maxTokens: 1024);
  }

  static Future<Map<String, dynamic>> extractInvoiceDataFromImage(File imageFile) async {
    final bytes       = await imageFile.readAsBytes();
    final base64Image = base64Encode(bytes);
    const prompt = '''
You are looking at a mobile phone shop PURCHASE INVOICE from Pakistan or India.
It may be handwritten, printed, or mixed. Read every part carefully.

Extract data and return ONLY valid JSON — no markdown, no explanation:
{
  "supplier_name": "string or null",
  "invoice_number": "string or null",
  "invoice_date": "YYYY-MM-DD or null",
  "items": [
    {
      "brand": "string",
      "model": "string",
      "storage": "string or null",
      "color": "string or null",
      "imei": "string or null",
      "quantity": 1,
      "unit_price": 0
    }
  ],
  "total_amount": 0
}

CRITICAL RULES:
1. supplier_name: the business/shop name in the letterhead or "From:" field
2. brand + model: may appear on separate lines below "BRAND" and "MODEL NO" labels
3. IMEI: exactly 15 digits. Strip any spaces between digits.
4. Prices: numbers only (strip Rs, PKR, /-)
5. invoice_date: convert any date format to YYYY-MM-DD
6. quantity defaults to 1 if not shown
''';

    return _callVision(base64Image, prompt, maxTokens: 2048);
  }

  // ── Core HTTP helpers with retry + model fallback ────────────────────────────

  static Future<Map<String, dynamic>> _callVision(
      String base64Image, String prompt, {int maxTokens = 1024}) async {
    // Try each vision model; for each, retry once on 503 before moving on
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
              {
                // /no_think disables Qwen's slow reasoning mode (ignored by other models)
                'role': 'system',
                'content':
                    '/no_think You extract invoice data from images. Respond with valid JSON only.',
              },
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
          final raw = jsonDecode(res.body)['choices'][0]['message']['content'] as String;
          return _parseJson(raw);
        }

        if (res.statusCode != 503) {
          // Hard error — don't retry
          throw Exception('Groq Vision error ($model): ${res.statusCode} ${res.body}');
        }
        // 503 = over capacity — loop to retry or try next model
      }
    }

    throw Exception('AI is currently busy. Please wait a moment and try again.');
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
          final raw = jsonDecode(res.body)['choices'][0]['message']['content'] as String;
          return _parseJson(raw);
        }

        if (res.statusCode != 503) {
          throw Exception('Groq API error ($model): ${res.statusCode} ${res.body}');
        }
      }
    }

    throw Exception('AI is currently busy. Please wait a moment and try again.');
  }

  /// Strip Qwen think blocks and markdown fences, then parse JSON
  static Map<String, dynamic> _parseJson(String raw) {
    final clean = raw
        .replaceAll(RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false), '')
        .replaceAll(RegExp(r'```json\s*'), '')
        .replaceAll(RegExp(r'```\s*'), '')
        .trim();
    return jsonDecode(clean) as Map<String, dynamic>;
  }
}
