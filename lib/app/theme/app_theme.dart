import 'package:flutter/material.dart';

ThemeData buildAppTheme(Brightness brightness) =>
    ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF2F6FED), brightness: brightness);
