import 'package:flutter/material.dart';

Widget buildMatterportEmbed({required String url}) {
  return const Center(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: Text(
        'Matterport embed currently runs on the web demo. Use the web target to test the interactive tour.',
        textAlign: TextAlign.center,
      ),
    ),
  );
}

bool get matterportEmbedSupported => false;
