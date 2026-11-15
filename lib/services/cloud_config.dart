import 'package:supabase_flutter/supabase_flutter.dart';

const mtandaoSupabaseUrl = String.fromEnvironment(
  'MTANDAO_SUPABASE_URL',
  defaultValue: 'https://supzoqcfzwrxdfbtqdzo.supabase.co',
);
const mtandaoSupabasePublishableKey = String.fromEnvironment(
  'MTANDAO_SUPABASE_PUBLISHABLE_KEY',
);
const mtandaoApiUrl = String.fromEnvironment('MTANDAO_API_URL');

class CloudConfig {
  static bool get isConfigured => mtandaoSupabasePublishableKey.isNotEmpty;
  static Uri get apiBaseUri {
    if (mtandaoApiUrl.isEmpty) {
      throw StateError('MTANDAO_API_URL is not configured');
    }
    final uri = Uri.tryParse(mtandaoApiUrl);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw StateError('MTANDAO_API_URL must be a valid HTTPS URL');
    }
    return uri;
  }

  static Future<void> initialize() async {
    if (!isConfigured) return;
    await Supabase.initialize(
      url: mtandaoSupabaseUrl,
      publishableKey: mtandaoSupabasePublishableKey,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
}
