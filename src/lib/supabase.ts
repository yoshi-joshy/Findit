import { createClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL as string | undefined
const key = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined
export const configured = Boolean(url && key && !url.includes('your-project'))
export const supabase = createClient(url || 'https://placeholder.supabase.co', key || 'placeholder-anon-key')

export type Item = {
  id: string; user_id: string; title: string; description: string; category: string; item_type: 'lost' | 'found'; location: string; item_date: string; image_url: string | null; colour: string | null; brand: string | null; additional_details: string | null; status: 'active' | 'resolved' | 'suspended'; created_at: string; profiles?: { display_name: string | null } | null
}
export const categories = ['Electronics','Bags and backpacks','Clothing','Jewellery','Keys','Wallets','Books and stationery','Sports equipment','Other']
export async function ensureProfile(userId:string, displayName?:string|null){
  const {data,error}=await supabase.from('profiles').select('id').eq('id',userId).maybeSingle()
  if(error)return error.message
  if(data)return null
  const {error:insertError}=await supabase.from('profiles').insert({id:userId,display_name:displayName?.trim().slice(0,60)||'Community member'})
  return insertError?.message||null
}
export function imageUrl(path: string | null) {
  if (!path) return ''
  if (path.startsWith('http')) return path
  return supabase.storage.from('item-images').getPublicUrl(path).data.publicUrl
}
