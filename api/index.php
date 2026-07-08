<?php
// ============================================================
//  MobileKhata REST API
//  Deploy entire /api/ folder to Hostinger public_html/mobilekhata-api/
// ============================================================

require_once 'config.php';

// ── CORS ─────────────────────────────────────────────────────
header('Access-Control-Allow-Origin: ' . ALLOWED_ORIGIN);
header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Content-Type: application/json; charset=utf-8');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

// ── DB connection ─────────────────────────────────────────────
function db(): PDO {
    static $pdo;
    if (!$pdo) {
        $pdo = new PDO(
            'mysql:host=' . DB_HOST . ';dbname=' . DB_NAME . ';charset=utf8mb4',
            DB_USER, DB_PASS,
            [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
             PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC]
        );
    }
    return $pdo;
}

// ── Helpers ───────────────────────────────────────────────────
function json_out(array $data, int $code = 200): void {
    http_response_code($code);
    echo json_encode($data, JSON_UNESCAPED_UNICODE);
    exit;
}

function body(): array {
    return (array) json_decode(file_get_contents('php://input'), true);
}

function require_field(array $data, string ...$fields): void {
    foreach ($fields as $f) {
        if (empty($data[$f])) json_out(['error' => "Missing field: $f"], 400);
    }
}

function auth_shop(): int {
    $h = $_SERVER['HTTP_AUTHORIZATION'] ?? $_SERVER['HTTP_X_AUTHORIZATION'] ?? '';
    $token = trim(str_replace('Bearer', '', $h));
    if (!$token) json_out(['error' => 'Unauthorized'], 401);
    $st = db()->prepare('SELECT id FROM shops WHERE api_token = ?');
    $st->execute([$token]);
    $row = $st->fetch();
    if (!$row) json_out(['error' => 'Invalid token'], 401);
    return (int)$row['id'];
}

function generate_token(): string {
    return bin2hex(random_bytes(32));
}

// ── Router ────────────────────────────────────────────────────
$method = $_SERVER['REQUEST_METHOD'];
$uri    = trim(parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH), '/');
// Strip base path if API lives in a subfolder e.g. mobilekhata-api/
$uri = preg_replace('#^mobilekhata-api/?#', '', $uri);
$parts = explode('/', $uri);
$resource  = $parts[0] ?? '';
$sub       = $parts[1] ?? '';
$id        = is_numeric($parts[1] ?? '') ? (int)$parts[1] : null;

// ── Auth ──────────────────────────────────────────────────────
if ($resource === 'auth') {

    // POST /auth/register
    if ($sub === 'register' && $method === 'POST') {
        $b = body();
        require_field($b, 'shop_name', 'owner_name', 'email', 'password');
        $email = strtolower(trim($b['email']));
        $st = db()->prepare('SELECT id FROM shops WHERE email = ?');
        $st->execute([$email]);
        if ($st->fetch()) json_out(['error' => 'Email already registered'], 409);
        $hash  = password_hash($b['password'], PASSWORD_DEFAULT);
        $token = generate_token();
        $st = db()->prepare(
            'INSERT INTO shops (shop_name, owner_name, phone, email, password_hash, api_token)
             VALUES (?,?,?,?,?,?)'
        );
        $st->execute([$b['shop_name'], $b['owner_name'], $b['phone'] ?? null, $email, $hash, $token]);
        json_out(['token' => $token, 'shop_id' => db()->lastInsertId()]);
    }

    // POST /auth/login
    if ($sub === 'login' && $method === 'POST') {
        $b = body();
        require_field($b, 'email', 'password');
        $email = strtolower(trim($b['email']));
        $st = db()->prepare('SELECT * FROM shops WHERE email = ?');
        $st->execute([$email]);
        $shop = $st->fetch();
        if (!$shop || !password_verify($b['password'], $shop['password_hash'])) {
            json_out(['error' => 'Invalid credentials'], 401);
        }
        json_out([
            'token'      => $shop['api_token'],
            'shop_id'    => $shop['id'],
            'shop_name'  => $shop['shop_name'],
            'owner_name' => $shop['owner_name'],
        ]);
    }
}

// ── Dashboard ─────────────────────────────────────────────────
if ($resource === 'dashboard' && $method === 'GET') {
    $shop_id = auth_shop();
    $today   = date('Y-m-d');

    $st = db()->prepare(
        'SELECT COUNT(*) AS count, COALESCE(SUM(total_amount),0) AS revenue,
                COALESCE(SUM(total_profit),0) AS profit
         FROM sales WHERE shop_id = ? AND sale_date = ?'
    );
    $st->execute([$shop_id, $today]);
    $today_stats = $st->fetch();

    $st = db()->prepare(
        'SELECT COUNT(*) AS count, COALESCE(SUM(total_amount),0) AS revenue,
                COALESCE(SUM(total_profit),0) AS profit
         FROM sales WHERE shop_id = ?
         AND MONTH(sale_date) = MONTH(CURDATE()) AND YEAR(sale_date) = YEAR(CURDATE())'
    );
    $st->execute([$shop_id]);
    $month_stats = $st->fetch();

    $st = db()->prepare(
        'SELECT COUNT(*) AS in_stock FROM inventory WHERE shop_id = ? AND status = "in_stock"'
    );
    $st->execute([$shop_id]);
    $stock = $st->fetch();

    // Last 5 sales
    $st = db()->prepare(
        'SELECT s.id, s.sale_date, s.total_amount, s.total_profit,
                s.customer_name, s.payment_method,
                COUNT(si.id) AS items
         FROM sales s
         LEFT JOIN sale_items si ON si.sale_id = s.id
         WHERE s.shop_id = ?
         GROUP BY s.id ORDER BY s.created_at DESC LIMIT 5'
    );
    $st->execute([$shop_id]);
    $recent_sales = $st->fetchAll();

    json_out([
        'today'        => $today_stats,
        'this_month'   => $month_stats,
        'in_stock'     => (int)$stock['in_stock'],
        'recent_sales' => $recent_sales,
    ]);
}

// ── Products ──────────────────────────────────────────────────
if ($resource === 'products') {
    $shop_id = auth_shop();

    // GET /products
    if ($method === 'GET') {
        $st = db()->prepare(
            'SELECT p.*, COUNT(i.id) AS in_stock
             FROM products p
             LEFT JOIN inventory i ON i.product_id = p.id AND i.shop_id = ? AND i.status = "in_stock"
             WHERE p.shop_id = ?
             GROUP BY p.id ORDER BY p.brand, p.model'
        );
        $st->execute([$shop_id, $shop_id]);
        json_out($st->fetchAll());
    }

    // POST /products
    if ($method === 'POST') {
        $b = body();
        require_field($b, 'brand', 'model');
        // Upsert — if exact combo exists return it
        $st = db()->prepare(
            'SELECT id FROM products WHERE shop_id=? AND brand=? AND model=?
             AND COALESCE(storage,"")=? AND COALESCE(color,"")=?'
        );
        $st->execute([$shop_id, $b['brand'], $b['model'], $b['storage'] ?? '', $b['color'] ?? '']);
        $existing = $st->fetch();
        if ($existing) json_out(['id' => (int)$existing['id'], 'created' => false]);
        $st = db()->prepare(
            'INSERT INTO products (shop_id, brand, model, storage, color) VALUES (?,?,?,?,?)'
        );
        $st->execute([$shop_id, $b['brand'], $b['model'], $b['storage'] ?? null, $b['color'] ?? null]);
        json_out(['id' => (int)db()->lastInsertId(), 'created' => true], 201);
    }
}

// ── Inventory ─────────────────────────────────────────────────
if ($resource === 'inventory') {
    $shop_id = auth_shop();

    // GET /inventory?status=in_stock&q=search
    if ($method === 'GET' && !$id) {
        $status = $_GET['status'] ?? 'in_stock';
        $q      = $_GET['q'] ?? '';
        $sql = 'SELECT i.*, p.brand, p.model, p.storage, p.color
                FROM inventory i
                JOIN products p ON p.id = i.product_id
                WHERE i.shop_id = ? AND i.status = ?';
        $params = [$shop_id, $status];
        if ($q) {
            $sql .= ' AND (i.imei LIKE ? OR p.brand LIKE ? OR p.model LIKE ?)';
            $like = "%$q%";
            $params = array_merge($params, [$like, $like, $like]);
        }
        $sql .= ' ORDER BY i.created_at DESC';
        $st = db()->prepare($sql);
        $st->execute($params);
        json_out($st->fetchAll());
    }
}

// ── Purchases ─────────────────────────────────────────────────
if ($resource === 'purchases') {
    $shop_id = auth_shop();

    // GET /purchases
    if ($method === 'GET' && !$id) {
        $st = db()->prepare(
            'SELECT p.*, COUNT(i.id) AS unit_count
             FROM purchases p
             LEFT JOIN inventory i ON i.purchase_id = p.id
             WHERE p.shop_id = ?
             GROUP BY p.id ORDER BY p.created_at DESC LIMIT 50'
        );
        $st->execute([$shop_id]);
        json_out($st->fetchAll());
    }

    // GET /purchases/{id}
    if ($method === 'GET' && $id) {
        $st = db()->prepare('SELECT * FROM purchases WHERE id = ? AND shop_id = ?');
        $st->execute([$id, $shop_id]);
        $purchase = $st->fetch();
        if (!$purchase) json_out(['error' => 'Not found'], 404);

        $st = db()->prepare(
            'SELECT i.*, p.brand, p.model, p.storage, p.color
             FROM inventory i JOIN products p ON p.id = i.product_id
             WHERE i.purchase_id = ? ORDER BY i.id'
        );
        $st->execute([$id]);
        $purchase['items'] = $st->fetchAll();
        json_out($purchase);
    }

    // POST /purchases  — body: {supplier_name, invoice_number, invoice_date, image_url, items:[{product_id, imei, unit_price}]}
    if ($method === 'POST') {
        $b = body();
        require_field($b, 'items');
        if (empty($b['items']) || !is_array($b['items'])) {
            json_out(['error' => 'items array required'], 400);
        }

        db()->beginTransaction();
        try {
            // Calculate total
            $total = array_sum(array_map(fn($it) => ($it['unit_price'] ?? 0) * ($it['quantity'] ?? 1), $b['items']));

            $st = db()->prepare(
                'INSERT INTO purchases (shop_id, supplier_name, invoice_number, invoice_date, total_amount, image_url, notes)
                 VALUES (?,?,?,?,?,?,?)'
            );
            $st->execute([
                $shop_id,
                $b['supplier_name'] ?? null,
                $b['invoice_number'] ?? null,
                $b['invoice_date'] ?? date('Y-m-d'),
                $total,
                $b['image_url'] ?? null,
                $b['notes'] ?? null,
            ]);
            $purchase_id = (int)db()->lastInsertId();

            foreach ($b['items'] as $item) {
                // Each item may have one IMEI or be quantity > 1 with multiple IMEIs
                $imeis = $item['imeis'] ?? ($item['imei'] ? [$item['imei']] : []);
                $qty   = max(1, (int)($item['quantity'] ?? 1));

                if (!empty($imeis)) {
                    foreach ($imeis as $imei) {
                        $st = db()->prepare(
                            'INSERT INTO inventory (shop_id, product_id, purchase_id, imei, purchase_price)
                             VALUES (?,?,?,?,?)'
                        );
                        $st->execute([$shop_id, $item['product_id'], $purchase_id,
                                      $imei ?: null, $item['unit_price']]);
                    }
                } else {
                    // No IMEIs — add quantity rows without IMEI
                    for ($i = 0; $i < $qty; $i++) {
                        $st = db()->prepare(
                            'INSERT INTO inventory (shop_id, product_id, purchase_id, imei, purchase_price)
                             VALUES (?,?,?,NULL,?)'
                        );
                        $st->execute([$shop_id, $item['product_id'], $purchase_id, $item['unit_price']]);
                    }
                }
            }

            db()->commit();
            json_out(['id' => $purchase_id, 'total' => $total], 201);
        } catch (Exception $e) {
            db()->rollBack();
            json_out(['error' => $e->getMessage()], 500);
        }
    }
}

// ── Sales ─────────────────────────────────────────────────────
if ($resource === 'sales') {
    $shop_id = auth_shop();

    // GET /sales
    if ($method === 'GET' && !$id) {
        $date_from = $_GET['from'] ?? date('Y-m-01');
        $date_to   = $_GET['to']   ?? date('Y-m-d');
        $st = db()->prepare(
            'SELECT s.*, COUNT(si.id) AS item_count
             FROM sales s
             LEFT JOIN sale_items si ON si.sale_id = s.id
             WHERE s.shop_id = ? AND s.sale_date BETWEEN ? AND ?
             GROUP BY s.id ORDER BY s.created_at DESC'
        );
        $st->execute([$shop_id, $date_from, $date_to]);
        json_out($st->fetchAll());
    }

    // GET /sales/{id}
    if ($method === 'GET' && $id) {
        $st = db()->prepare('SELECT * FROM sales WHERE id = ? AND shop_id = ?');
        $st->execute([$id, $shop_id]);
        $sale = $st->fetch();
        if (!$sale) json_out(['error' => 'Not found'], 404);

        $st = db()->prepare(
            'SELECT si.*, i.imei, p.brand, p.model, p.storage, p.color
             FROM sale_items si
             JOIN inventory i ON i.id = si.inventory_id
             JOIN products  p ON p.id = i.product_id
             WHERE si.sale_id = ?'
        );
        $st->execute([$id]);
        $sale['items'] = $st->fetchAll();
        json_out($sale);
    }

    // POST /sales — body: {customer_name, customer_phone, payment_method, items:[{inventory_id, sale_price}]}
    if ($method === 'POST') {
        $b = body();
        require_field($b, 'items');
        if (empty($b['items']) || !is_array($b['items'])) {
            json_out(['error' => 'items array required'], 400);
        }

        db()->beginTransaction();
        try {
            $total_amount = 0;
            $total_cost   = 0;

            // Validate & fetch purchase prices
            $enriched = [];
            foreach ($b['items'] as $item) {
                require_field($item, 'inventory_id', 'sale_price');
                $st = db()->prepare(
                    'SELECT id, purchase_price, status FROM inventory WHERE id = ? AND shop_id = ?'
                );
                $st->execute([$item['inventory_id'], $shop_id]);
                $inv = $st->fetch();
                if (!$inv) json_out(['error' => "Inventory item {$item['inventory_id']} not found"], 404);
                if ($inv['status'] === 'sold') json_out(['error' => "Item {$item['inventory_id']} already sold"], 409);

                $total_amount += $item['sale_price'];
                $total_cost   += $inv['purchase_price'];
                $enriched[]    = [
                    'inventory_id'   => $item['inventory_id'],
                    'sale_price'     => $item['sale_price'],
                    'purchase_price' => $inv['purchase_price'],
                    'profit'         => $item['sale_price'] - $inv['purchase_price'],
                ];
            }

            $total_profit = $total_amount - $total_cost;

            $st = db()->prepare(
                'INSERT INTO sales (shop_id, customer_name, customer_phone, sale_date,
                 total_amount, total_cost, total_profit, payment_method, notes)
                 VALUES (?,?,?,?,?,?,?,?,?)'
            );
            $st->execute([
                $shop_id,
                $b['customer_name']  ?? null,
                $b['customer_phone'] ?? null,
                $b['sale_date']      ?? date('Y-m-d'),
                $total_amount,
                $total_cost,
                $total_profit,
                $b['payment_method'] ?? 'cash',
                $b['notes']          ?? null,
            ]);
            $sale_id = (int)db()->lastInsertId();

            foreach ($enriched as $e) {
                $st = db()->prepare(
                    'INSERT INTO sale_items (sale_id, inventory_id, sale_price, purchase_price, profit)
                     VALUES (?,?,?,?,?)'
                );
                $st->execute([$sale_id, $e['inventory_id'], $e['sale_price'], $e['purchase_price'], $e['profit']]);

                // Mark inventory as sold
                $st = db()->prepare('UPDATE inventory SET status = "sold" WHERE id = ?');
                $st->execute([$e['inventory_id']]);
            }

            db()->commit();
            json_out([
                'id'           => $sale_id,
                'total_amount' => $total_amount,
                'total_profit' => $total_profit,
            ], 201);
        } catch (Exception $e) {
            db()->rollBack();
            json_out(['error' => $e->getMessage()], 500);
        }
    }
}

// ── 404 ───────────────────────────────────────────────────────
json_out(['error' => 'Endpoint not found'], 404);
