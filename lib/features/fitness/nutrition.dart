import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/cortex.dart';
import '../../core/navigation.dart';
import '../../app/ui.dart';
import '../../main.dart';

const nutrientLabels = {
  'kcal': 'Energy',
  'protein_g': 'Protein',
  'carbs_g': 'Carbs',
  'fat_g': 'Fat',
  'saturated_fat_g': 'Saturated fat',
  'fiber_g': 'Fibre',
  'added_sugar_g': 'Added sugar',
  'sodium_mg': 'Sodium',
};

String nutrientUnit(String key) => key == 'kcal'
    ? 'kcal'
    : key == 'sodium_mg'
    ? 'mg'
    : 'g';
String nutritionNumber(num n) =>
    n == n.roundToDouble() ? n.toInt().toString() : n.toStringAsFixed(1);
Map<String, dynamic> nutrientsOf(Map data) {
  final value = data['nutrients'];
  // Old calorie-only logs must not silently become zero-protein/sugar meals.
  return value is Map
      ? Map<String, dynamic>.from(value)
      : {if (data['kcal'] is num) 'kcal': data['kcal']};
}

class NutritionTotal {
  final double value;
  final int known, count;
  final bool estimated;
  const NutritionTotal(this.value, this.known, this.count, this.estimated);
  bool get partial => known < count;
}

Map<String, NutritionTotal> totalNutrition(List<Entry> meals) => {
  for (final key in nutrientLabels.keys)
    key: (() {
      double value = 0;
      var known = 0, estimated = false;
      for (final meal in meals) {
        final n = nutrientsOf(meal.data)[key];
        if (n is! num || !n.isFinite) continue;
        value += n;
        known++;
        estimated |=
            (meal.data['estimated'] as List? ?? []).contains(key) ||
            meal.data['portionEstimated'] == true;
      }
      return NutritionTotal(value, known, meals.length, estimated);
    })(),
};

IconData foodIcon(String? category) => switch (category) {
  'vegetable' => Icons.eco_outlined,
  'fruit' => Icons.apple_outlined,
  'grain' => Icons.bakery_dining_outlined,
  'protein' => Icons.set_meal_outlined,
  'dairy' => Icons.breakfast_dining_outlined,
  'drink' => Icons.local_drink_outlined,
  'snack' => Icons.cookie_outlined,
  _ => Icons.restaurant_outlined,
};

// Portion-specific flags use the FDA's general 20% Daily Value convention.
// These are label-reading aids, not owner calorie targets or a diagnosis.
List<String> nutritionFlags(Map<String, dynamic> nutrients) {
  final flags = <String>[];
  for (final rule in [
    ('sodium_mg', 460, 'High sodium'),
    ('added_sugar_g', 10, 'High added sugar'),
    ('saturated_fat_g', 4, 'High saturated fat'),
  ]) {
    final value = nutrients[rule.$1];
    if (value is num && value >= rule.$2) flags.add(rule.$3);
  }
  final fibre = nutrients['fiber_g'];
  if (fibre is num && fibre >= 5.6) flags.add('High fibre');
  return flags;
}

class NutritionGrid extends StatelessWidget {
  final Map<String, NutritionTotal> totals;
  const NutritionGrid({super.key, required this.totals});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => Wrap(
      spacing: 12,
      runSpacing: 14,
      children: [
        for (final key in nutrientLabels.keys)
          SizedBox(
            width: (box.maxWidth - 12) / 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                caption(nutrientLabels[key]!),
                Text(
                  totals[key]!.known == 0
                      ? '—'
                      : '${totals[key]!.estimated ? '~' : ''}${nutritionNumber(totals[key]!.value)} ${nutrientUnit(key)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (totals[key]!.known > 0 && totals[key]!.partial)
                  caption(
                    '${totals[key]!.known}/${totals[key]!.count} meals known',
                  ),
              ],
            ),
          ),
      ],
    ),
  );
}

class FoodFactsTile extends StatelessWidget {
  final Entry entry;
  final bool library;
  final OpenChat onChat;
  const FoodFactsTile({
    super.key,
    required this.entry,
    required this.onChat,
    this.library = false,
  });
  @override
  Widget build(BuildContext context) {
    final d = entry.data;
    final facts = nutrientsOf(d);
    final estimated = d['estimated'] as List? ?? [];
    final flags = nutritionFlags(facts);
    final watch = flags.any((f) => f != 'High fibre');
    final known = [
      'sodium_mg',
      'added_sugar_g',
      'saturated_fat_g',
    ].every((k) => facts[k] is num);
    final rating = watch
        ? 'Mind the portion'
        : flags.contains('High fibre')
        ? 'Fibre-rich choice'
        : known
        ? 'No high flags'
        : 'Partial facts';
    final items = d['items'] as List? ?? [];
    final firstFood = items.length == 1
        ? (items.first as Map)['food'] as Map?
        : null;
    final category = library
        ? d['category']?.toString()
        : firstFood?['category']?.toString() ?? 'mixed';
    final portion = d['portion'] as Map?;
    final title = (d[library ? 'name' : 'title'] ?? 'Food').toString();
    final basis = library && portion != null
        ? 'Per ${nutritionNumber(portion['amount'] as num)} ${portion['unit']}${portion['description'] == null ? '' : ' · ${portion['description']}'}'
        : items.isEmpty
        ? 'Recorded portion'
        : items
              .map((item) {
                final food = item['food'] as Map;
                return '${nutritionNumber(item['amount'] as num)} ${food['portion']['unit']} ${food['name']}';
              })
              .join(' · ');
    final sources = <String>{
      ...((d['sources'] as List? ?? []).map((e) => e.toString())),
      for (final item in items)
        ...(((item as Map)['food']['sources'] as List? ?? []).map(
          (e) => e.toString(),
        )),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Panel(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 14),
          leading: CircleAvatar(
            backgroundColor: soft,
            foregroundColor: ink,
            child: Icon(foodIcon(category)),
          ),
          title: Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            '${facts['kcal'] == null ? 'Energy unknown' : '${estimated.contains('kcal') || d['portionEstimated'] == true ? '~' : ''}${nutritionNumber(facts['kcal'] as num)} kcal'} · $rating',
            style: const TextStyle(fontSize: 12),
          ),
          children: [
            Align(alignment: Alignment.centerLeft, child: caption(basis)),
            const SizedBox(height: 14),
            NutritionGrid(totals: totalNutrition([Entry(entry.id, 'meal', d)])),
            const SizedBox(height: 12),
            if (flags.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 6,
                  children: [
                    for (final flag in flags)
                      Chip(
                        label: Text(flag, style: const TextStyle(fontSize: 11)),
                        backgroundColor: flag == 'High fibre'
                            ? soft
                            : const Color(0xFFFFF2DB),
                        side: BorderSide.none,
                      ),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: caption(
                '~ Estimated · — Not enough information.\nFlags apply to the portion above. High = at least 20% of a general daily reference; this is not a personal target.',
              ),
            ),
            if ((d['notes']?.toString() ?? '').isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: caption(d['notes'].toString()),
              ),
            if (sources.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  children: [
                    for (final source in sources)
                      TextButton(
                        onPressed: () => launchUrl(
                          Uri.parse(source),
                          mode: LaunchMode.externalApplication,
                        ),
                        child: Text(
                          Uri.tryParse(source)?.host ?? 'Source',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => launchUrl(
                  Uri.parse(
                    'https://www.fda.gov/food/nutrition-facts-label/how-understand-and-use-nutrition-facts-label',
                  ),
                  mode: LaunchMode.externalApplication,
                ),
                child: const Text(
                  'How nutrition flags work',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () {
                  if (library) Navigator.of(context).pop();
                  onChat(
                    library
                        ? 'I ate $title. Use saved food ${entry.id}. My portion: '
                        : 'About my meal “$title” on ${d['date']} (mealId ${entry.id}): ',
                  );
                },
                icon: const Icon(Icons.chat_bubble_outline, size: 17),
                label: Text(
                  library ? 'Tell Cortex I ate this' : 'Discuss this meal',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FoodToday extends StatelessWidget {
  final CortexModel model;
  final List<Entry> meals;
  final OpenChat onChat;
  const FoodToday({
    super.key,
    required this.model,
    required this.meals,
    required this.onChat,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      sectionHead('Nutrition today'),
      if (meals.isEmpty)
        caption('Send a photo or tell Cortex what you ate.')
      else
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NutritionGrid(totals: totalNutrition(meals)),
              const SizedBox(height: 12),
              caption(
                '~ Includes estimates. Unknown values stay blank; partial totals only include known meals.',
              ),
            ],
          ),
        ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => FoodLibrary(model: model, onChat: onChat),
          ),
        ),
        icon: const Icon(Icons.menu_book_outlined, size: 18),
        label: const Text('Saved food facts'),
      ),
      if (meals.isNotEmpty) sectionHead('Food today'),
      for (final meal in meals) FoodFactsTile(entry: meal, onChat: onChat),
    ],
  );
}

class FoodLibrary extends StatefulWidget {
  final CortexModel model;
  final OpenChat onChat;
  const FoodLibrary({super.key, required this.model, required this.onChat});
  @override
  State<FoodLibrary> createState() => _FoodLibraryState();
}

class _FoodLibraryState extends State<FoodLibrary> {
  final query = TextEditingController();
  List<Entry> rows = [];
  int? next;
  int generation = 0;
  bool loading = true;
  String? error;
  Timer? debounce;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    debounce?.cancel();
    query.dispose();
    super.dispose();
  }

  Future<void> load({bool more = false}) async {
    final request = ++generation;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result =
          await widget.model.api.call(
                'GET',
                '/v1/foods?q=${Uri.encodeQueryComponent(query.text.trim())}&offset=${more ? next ?? 0 : 0}',
              )
              as Map;
      if (!mounted || request != generation) return;
      final entries = (result['records'] as List)
          .map((r) => Entry.fromJson(Map<String, dynamic>.from(r)))
          .toList();
      setState(() {
        rows = more ? [...rows, ...entries] : entries;
        next = (result['nextOffset'] as num?)?.toInt();
      });
    } catch (e) {
      if (mounted && request == generation) {
        setState(() => error = e.toString());
      }
    } finally {
      if (mounted && request == generation) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => KeyboardDismissBar(
    child: Scaffold(
      backgroundColor: const Color(0xFFF7F9F3),
      appBar: AppBar(title: const Text('Saved food facts')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          caption(
            'Food names and nutrition, ready to reuse. Tell Cortex when a portion or recipe changes.',
          ),
          const SizedBox(height: 14),
          TextField(
            controller: query,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Find a food',
            ),
            onChanged: (_) {
              debounce?.cancel();
              generation++;
              debounce = Timer(const Duration(milliseconds: 350), () => load());
            },
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              widget.onChat(
                'Infer the nutrition facts from this photo and save the food name and facts for reuse. This is a reference only, not food I ate.',
                photo: true,
              );
            },
            icon: const Icon(Icons.add_a_photo_outlined),
            label: const Text('Add food facts from a photo'),
          ),
          if (loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (error != null)
            TextButton(
              onPressed: load,
              child: Text('Could not load foods. Tap to retry.\n$error'),
            ),
          if (!loading && error == null && rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: caption(
                query.text.isEmpty
                    ? 'No saved foods yet. Send a food or nutrition-facts photo to Cortex.'
                    : 'No matching foods. Try a shorter name.',
              ),
            ),
          for (final food in rows)
            FoodFactsTile(entry: food, onChat: widget.onChat, library: true),
          if (next != null && !loading && error == null)
            TextButton(
              onPressed: () => load(more: true),
              child: const Text('Load more foods'),
            ),
        ],
      ),
    ),
  );
}
