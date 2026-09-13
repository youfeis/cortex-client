import '../../remote_ui/remote_layout.dart';
import 'package:flutter/material.dart';
import '../../core/cortex.dart';
import '../../main.dart';
import 'section_art.dart';

import '../fitness/fitness_screen.dart';
import '../time/time_screen.dart';
import '../pets/pets_screen.dart';
import '../../core/navigation.dart';

class SpaceScreen extends StatelessWidget {
  final CortexModel model;
  final OpenChat onChat;
  const SpaceScreen({super.key, required this.model, required this.onChat});
  @override
  Widget build(BuildContext context) => RemoteLayout(
    page: 'space',
    slots: {
      'time': area(
        context,
        'Time\nmanagement',
        'A day with breathing room',
        Icons.schedule_rounded,
        () => open(context, 'time'),
      ),
      'fitness': area(
        context,
        'Fitness',
        'Small steps, visible progress',
        Icons.favorite_border_rounded,
        () => open(context, 'fitness'),
      ),
      'pets': area(
        context,
        'Pets',
        'Cookie & Wanwan',
        Icons.pets_rounded,
        () => open(context, 'pets'),
      ),
      'money': area(
        context,
        'Money\nspending',
        'Later',
        Icons.account_balance_wallet_outlined,
        null,
      ),
      'targets': area(
        context,
        'Personal\ntargets',
        'Later',
        Icons.flag_outlined,
        null,
      ),
    },
  );
  Widget area(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
    VoidCallback? tap,
  ) => Material(
    color: tap == null ? const Color(0xFFF2F4EE) : Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: const BorderSide(color: line),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: tap,
      child: Padding(
        padding: const EdgeInsets.all(19),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (tap != null)
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: icon == Icons.pets_rounded
                        ? const PetSectionArt()
                        : SectionArt(
                            fitness: icon == Icons.favorite_border_rounded,
                          ),
                  ),
                ),
              )
            else
              const Spacer(),
            Text(
              title,
              style: TextStyle(
                fontSize: 19,
                height: 1.2,
                fontWeight: FontWeight.w600,
                color: tap == null ? muted : ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(subtitle, style: const TextStyle(fontSize: 11, color: muted)),
          ],
        ),
      ),
    ),
  );
  void open(BuildContext context, String section) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (pageContext) {
        void backToChat(String prompt, {bool photo = false}) {
          Navigator.pop(pageContext);
          onChat(prompt, photo: photo);
        }

        return switch (section) {
          'fitness' => FitnessScreen(model: model, onChat: backToChat),
          'pets' => PetsScreen(model: model, onChat: backToChat),
          _ => TimeScreen(model: model, onChat: backToChat),
        };
      },
    ),
  );
}
