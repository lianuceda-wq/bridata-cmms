import MaterialCostPanel from './MaterialCostPanel'

export default async function WorkOrderInventoryLayout({
  children,
  params,
}: {
  children: React.ReactNode
  params: Promise<{ id: string }>
}) {
  const { id } = await params
  return (
    <>
      {children}
      <div className="content" style={{ paddingTop: 0 }}>
        <MaterialCostPanel workOrderId={id} />
      </div>
    </>
  )
}
