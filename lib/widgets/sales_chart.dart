import 'package:flutter/material.dart';

/// Histogramme simple des ventes (une barre par jour ou par heure).
class SalesBarChart extends StatelessWidget {
  const SalesBarChart({
    super.key,
    required this.values,
    required this.labelOf,
    this.height = 120,
  });

  final List<int> values;

  /// Libellé de l'axe pour la barre [i] (null : pas de libellé).
  final String? Function(int i) labelOf;
  final double height;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final textStyle = Theme.of(context).textTheme.labelSmall;
    final max = values.fold<int>(0, (a, b) => b > a ? b : a);
    return SizedBox(
      height: height + 18,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < values.length; i++)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    height: max == 0 ? 1 : (values[i] / max * height).clamp(values[i] > 0 ? 2.0 : 1.0, height),
                    decoration: BoxDecoration(
                      color: values[i] > 0 ? color : color.withValues(alpha: 0.2),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                    ),
                  ),
                  SizedBox(
                    height: 18,
                    child: labelOf(i) == null
                        ? null
                        : FittedBox(child: Text(labelOf(i)!, style: textStyle)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
