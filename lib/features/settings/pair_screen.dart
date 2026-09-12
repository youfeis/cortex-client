import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/cortex.dart';
import '../../main.dart';
import '../../app/ui.dart';

class PairScreen extends StatefulWidget {
  final CortexModel model;
  const PairScreen({super.key, required this.model});
  @override
  State<PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends State<PairScreen> {
  final code = TextEditingController();
  bool pairing = false;
  String? error;
  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  Future<void> pair() async {
    setState(() {
      pairing = true;
      error = null;
    });
    try {
      await widget.model.pair(code.text);
    } catch (e) {
      if (mounted) {
        setState(() {
          pairing = false;
          error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.psychology_outlined, size: 52, color: ink),
              const SizedBox(height: 28),
              label('JUST FOR YOU'),
              const SizedBox(height: 12),
              const Text(
                'A little less\nto hold in your head.',
                style: TextStyle(
                  fontSize: 33,
                  height: 1.16,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 20),
              caption('External Prefrontal Cortex'),
              const SizedBox(height: 36),
              titleText('Pair this iPhone'),
              const SizedBox(height: 10),
              caption(
                'Paste your one-time pairing code. This device will get its own private key.',
              ),
              const SizedBox(height: 20),
              TextField(
                key: const Key('pairing-code'),
                controller: code,
                enabled: !pairing,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'Pairing code',
                  suffixIcon: IconButton(
                    tooltip: 'Paste code',
                    onPressed: () async {
                      final data = await Clipboard.getData(
                        Clipboard.kTextPlain,
                      );
                      if (data?.text != null) {
                        code.text = data!.text!.trim();
                      }
                    },
                    icon: const Icon(Icons.content_paste_outlined),
                  ),
                ),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error!,
                    style: const TextStyle(color: Colors.deepOrange),
                  ),
                ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('pair-device'),
                  onPressed: pairing ? null : pair,
                  child: Text(pairing ? 'Pairing…' : 'Pair my device'),
                ),
              ),
              const SizedBox(height: 20),
              caption('cortex.miaotutu.com · Private connection'),
            ],
          ),
        ),
      ),
    ),
  );
}
