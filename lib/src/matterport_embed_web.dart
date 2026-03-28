import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';

final Set<String> _registeredViewTypes = <String>{};

Widget buildMatterportEmbed({required String url}) {
  final viewType = 'matterport-${url.hashCode}';

  if (_registeredViewTypes.add(viewType)) {
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
      final iframe = html.IFrameElement()
        ..src = url
        ..style.border = '0'
        ..style.width = '100%'
        ..style.height = '100%'
        ..allowFullscreen = true
        ..allow = 'fullscreen; xr-spatial-tracking; vr';
      return iframe;
    });
  }

  return HtmlElementView(viewType: viewType);
}

bool get matterportEmbedSupported => true;
