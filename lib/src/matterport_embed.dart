import 'package:flutter/widgets.dart';

import 'matterport_embed_stub.dart'
    if (dart.library.html) 'matterport_embed_web.dart' as impl;

Widget buildMatterportEmbed({required String url}) {
  return impl.buildMatterportEmbed(url: url);
}

bool get matterportEmbedSupported => impl.matterportEmbedSupported;
