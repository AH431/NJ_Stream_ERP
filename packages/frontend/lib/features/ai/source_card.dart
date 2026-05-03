import 'package:flutter/material.dart';

import '../../providers/ai_provider.dart';

class SourceCard extends StatelessWidget {
  final ChatSource source;
  const SourceCard(this.source, {super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = _toolLabel(source.tool);
    final subtitle = source.resourceId != null
        ? '${source.resourceType} · ${source.resourceId}'
        : source.resourceType;

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 4),
        leading: Icon(Icons.data_usage_outlined, size: 16, color: cs.primary),
        title: Text(
          label,
          style: TextStyle(fontSize: 12, color: cs.primary),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(fontSize: 11, color: cs.outline),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _row('工具', source.tool, cs),
                _row('類型', source.resourceType, cs),
                if (source.resourceId != null)
                  _row('資源 ID', source.resourceId!, cs),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, ColorScheme cs) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 56,
          child: Text(
            label,
            style: TextStyle(fontSize: 11, color: cs.outline),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 11),
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ),
      ],
    ),
  );

  static String _toolLabel(String tool) => switch (tool) {
    'get_inventory'    => '庫存查詢',
    'get_quotation'    => '報價查詢',
    'get_sales_order'  => '訂單查詢',
    'search_customers' => '客戶查詢',
    _                  => tool,
  };
}
