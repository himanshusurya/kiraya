import 'package:kiraya_core/kiraya_core.dart';
import 'package:material_ui/material_ui.dart';

const kTenantSeed = Color(0xFF3949AB);

/// Core's big, easy-to-read theme in the tenant app's indigo.
ThemeData tenantTheme({Color seed = kTenantSeed}) => kirayaTheme(seed: seed);
