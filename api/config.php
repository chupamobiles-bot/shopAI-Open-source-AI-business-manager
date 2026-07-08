<?php
// ============================================================
//  MobileKhata API — Configuration
//  Rename this file and fill your Hostinger DB credentials
// ============================================================

define('DB_HOST', 'localhost');
define('DB_NAME', 'mobilekhata');      // your Hostinger DB name
define('DB_USER', 'your_db_user');     // your Hostinger DB username
define('DB_PASS', 'your_db_password'); // your Hostinger DB password

define('JWT_SECRET', 'change_this_to_a_random_64char_string_xyz123');

// CORS — set to your domain or * for development
define('ALLOWED_ORIGIN', '*');
