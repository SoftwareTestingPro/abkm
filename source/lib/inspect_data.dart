import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  final supabase = SupabaseClient(
    'https://dusxuppoolkwuaosavlt.supabase.co', 
    'sb_publishable_ptryFr0b7vE0j3AVOp0MBg_8CHEBoyc'
  );

  try {
    print('Fetching one row from india_locations...');
    final response = await supabase
        .from('india_locations')
        .select('state, district, tehsil, village')
        .limit(1);
    print('Sample Data: $response');
  } catch (e) {
    print('Error: $e');
  }
}
