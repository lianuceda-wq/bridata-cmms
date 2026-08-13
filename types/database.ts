export type WorkOrderStatus =
  | 'requested'
  | 'planned'
  | 'assigned'
  | 'in_progress'
  | 'paused'
  | 'completed'
  | 'validated'
  | 'closed'
  | 'cancelled'

export type AssetStatus = 'operational' | 'maintenance' | 'stopped' | 'retired'
