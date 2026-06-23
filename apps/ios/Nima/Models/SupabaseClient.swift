import Foundation
import Supabase

let supabaseClient: Supabase.SupabaseClient? = {
    guard let urlString = Bundle.main.infoDictionary?["SUPABASE_URL"] as? String,
          let url = URL(string: urlString),
          let key = Bundle.main.infoDictionary?["SUPABASE_KEY"] as? String else {
        return nil
    }
    return Supabase.SupabaseClient(supabaseURL: url, supabaseKey: key)
}()
