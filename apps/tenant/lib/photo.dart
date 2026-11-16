import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:kiraya_core/kiraya_core.dart';
import 'package:material_ui/material_ui.dart';

/// Picks a compressed photo. With [askSource] the user chooses Camera or Gallery,
/// otherwise the gallery opens directly (payment screenshots).
Future<Uint8List?> pickPhoto(BuildContext context, {bool askSource = false}) async {
  var source = ImageSource.gallery;
  if (askSource) {
    final s = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_camera),
            title: Text(tr('camera')),
            onTap: () => Navigator.pop(c, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: Text(tr('gallery')),
            onTap: () => Navigator.pop(c, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (s == null) return null;
    source = s;
  }
  try {
    final x = await ImagePicker().pickImage(source: source, imageQuality: 60, maxWidth: 1600);
    return x == null ? null : await x.readAsBytes();
  } catch (e) {
    if (context.mounted) showMessage(context, friendlyError(e), error: true);
    return null;
  }
}

/// "Add photo" button that turns into "Photo added ✓  [Remove]" once picked.
class PhotoPickButton extends StatelessWidget {
  const PhotoPickButton({
    super.key,
    required this.label,
    required this.addedLabel,
    required this.hasPhoto,
    required this.onPick,
    required this.onRemove,
  });
  final String label, addedLabel;
  final bool hasPhoto;
  final VoidCallback? onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    if (!hasPhoto) return BigButton(label: label, icon: Icons.add_a_photo, outlined: true, onPressed: onPick);
    return Row(children: [
      const Icon(Icons.check_circle, color: kGood),
      const SizedBox(width: 8),
      Expanded(child: Text(addedLabel, style: const TextStyle(fontWeight: FontWeight.w600))),
      TextButton(onPressed: onRemove, child: Text(tr('remove'))),
    ]);
  }
}
