<?php
// ─────────────────────────────────────────────────────────────────────────────
// ShopAI — New endpoints to add to your index.php
// These make the web dashboard work and expose business type info.
// Copy-paste these route blocks into your index.php file.
// ─────────────────────────────────────────────────────────────────────────────

// ── GET /shop ─────────────────────────────────────────────────────────────────
// Returns shop info + business type — used by the web dashboard header.
if ($path === '/shop' && $method === 'GET') {
    $sid = get_shop_id();
    $st = $pdo->prepare('SELECT id, shop_name, business_type, currency, currency_symbol FROM shops WHERE id=?');
    $st->execute([$sid]);
    $shop = $st->fetch();
    json_ok([
        'id'              => $shop['id'],
        'name'            => $shop['shop_name'],
        'business_type'   => $shop['business_type'] ?? 'General Store',
        'currency'        => $shop['currency'] ?? 'PKR',
        'currency_symbol' => $shop['currency_symbol'] ?? 'Rs',
    ]);
}

// ── PATCH /shop ───────────────────────────────────────────────────────────────
// Update business type, currency, etc.
if ($path === '/shop' && $method === 'PATCH') {
    $sid = get_shop_id();
    $st = $pdo->prepare(
        'UPDATE shops SET
           business_type   = COALESCE(?, business_type),
           currency        = COALESCE(?, currency),
           currency_symbol = COALESCE(?, currency_symbol)
         WHERE id=?'
    );
    $st->execute([
        $body['business_type']   ?? null,
        $body['currency']        ?? null,
        $body['currency_symbol'] ?? null,
        $sid,
    ]);
    json_ok(['ok' => true]);
}

// ── GET /inventory ────────────────────────────────────────────────────────────
// Generic inventory — returns products with their fields JSON parsed.
// ADD THIS if your existing /inventory endpoint doesn't return fields.
if ($path === '/inventory' && $method === 'GET') {
    $sid = get_shop_id();
    $st = $pdo->prepare(
        'SELECT p.id, p.brand, p.model, p.storage, p.color, p.fields,
                i.quantity, i.status, i.purchase_price, i.imei, i.identifier
         FROM products p
         JOIN inventory i ON i.product_id = p.id
         WHERE i.shop_id = ? AND i.status = "in_stock"
         ORDER BY i.id DESC'
    );
    $st->execute([$sid]);
    $rows = $st->fetchAll();

    // Merge generic fields with legacy brand/model columns
    foreach ($rows as &$row) {
        $extra = $row['fields'] ? json_decode($row['fields'], true) : [];
        if (empty($extra) && $row['brand']) {
            $extra = ['brand' => $row['brand'], 'model' => $row['model'],
                      'storage' => $row['storage'], 'color' => $row['color']];
        }
        $row['fields'] = json_encode($extra);

        // Use generic identifier if imei is empty
        if (empty($row['imei']) && !empty($row['identifier'])) {
            $row['imei'] = $row['identifier'];
        }
        // Build a display name
        $row['name'] = trim(($extra['brand'] ?? '') . ' ' . ($extra['model'] ?? ''));
        if (empty($row['name'])) $row['name'] = $extra['name'] ?? 'Unknown';
    }

    json_ok($rows);
}

// ── POST /products (generic) ──────────────────────────────────────────────────
// Creates a product with arbitrary fields JSON.
// This replaces the phone-specific product creation if you want full generalization.
// Your existing endpoint still works — this is the generic version.
if ($path === '/products/generic' && $method === 'POST') {
    $sid = get_shop_id();
    if (empty($body['name']) && empty($body['fields'])) {
        json_error('name or fields is required');
    }

    $fields = $body['fields'] ?? [];
    // Extract name from fields if not provided
    $name = $body['name'] ?? ($fields['name'] ?? ($fields['brand'] . ' ' . ($fields['model'] ?? '')) ?? 'Unknown');

    // Check if product already exists (by name + fields hash)
    $fieldsJson = json_encode($fields);
    $st = $pdo->prepare('SELECT id FROM products WHERE shop_id=? AND name=? AND COALESCE(fields,"")=?');
    $st->execute([$sid, $name, $fieldsJson]);
    $existing = $st->fetch();

    if ($existing) {
        json_ok(['id' => $existing['id'], 'created' => false]);
    }

    $st = $pdo->prepare(
        'INSERT INTO products (shop_id, name, brand, model, storage, color, fields)
         VALUES (?, ?, ?, ?, ?, ?, ?)'
    );
    $st->execute([
        $sid,
        $name,
        $fields['brand']   ?? null,
        $fields['model']   ?? null,
        $fields['storage'] ?? null,
        $fields['color']   ?? null,
        $fieldsJson,
    ]);
    json_ok(['id' => $pdo->lastInsertId(), 'created' => true]);
}
