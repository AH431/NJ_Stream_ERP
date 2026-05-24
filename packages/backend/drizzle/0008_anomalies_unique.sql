-- 防止同一實體（entity_type + entity_id）在同一 alertType 有多筆未解除異常，
-- 消除 AnomalyScanner 並發或重跑時可能插入重複列的 race condition。
-- 使用 partial unique index（WHERE is_resolved = FALSE）允許同一實體在解除後重新觸發相同類型的異常。
CREATE UNIQUE INDEX IF NOT EXISTS "uq_anomalies_active_alert"
  ON "anomalies" ("entity_type", "entity_id", "alert_type")
  WHERE (is_resolved = FALSE);
