class AppConfig {
  // ── API ───────────────────────────────────────────────────
  // Replace with your server URL (see backend/index.php)
  static const apiBaseUrl = 'https://your-server.com/api';

  // ── Groq (free AI for invoice extraction) ─────────────────
  // Get your free key at: https://console.groq.com
  static const groqApiKey = 'gsk_your_groq_api_key_here';

  // ── Cloudinary (invoice image storage — optional) ──────────
  // Leave as-is if you don't want image uploads
  static const cloudinaryCloudName    = 'YOUR_CLOUD_NAME';
  static const cloudinaryUploadPreset = 'YOUR_UPLOAD_PRESET';
}
