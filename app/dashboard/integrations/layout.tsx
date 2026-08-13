import Link from 'next/link'

export default function IntegrationsLayout({children}:{children:React.ReactNode}){
 return <div className="stack"><nav className="card" style={{display:'flex',gap:8,flexWrap:'wrap'}}><Link className="button button-secondary button-compact" href="/dashboard/integrations">Conexiones y Outbox</Link><Link className="button button-secondary button-compact" href="/dashboard/integrations/inbound">Inbound API</Link></nav>{children}</div>
}
