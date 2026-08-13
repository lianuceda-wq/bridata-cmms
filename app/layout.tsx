import './globals.css'

export const metadata = {
  title: 'Bridata CMMS',
  description: 'SaaS multi-tenant para gestión de mantenimiento'
}

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="es">
      <body>{children}</body>
    </html>
  )
}
