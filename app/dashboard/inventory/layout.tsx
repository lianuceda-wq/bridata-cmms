import PurchaseCancellationPanel from './PurchaseCancellationPanel'

export default function InventoryLayout({children}:{children:React.ReactNode}){
  return <>
    {children}
    <div className="content" style={{paddingTop:0}}>
      <PurchaseCancellationPanel/>
    </div>
  </>
}
