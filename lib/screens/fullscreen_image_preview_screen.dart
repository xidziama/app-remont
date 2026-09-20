import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Reusable fullscreen image preview.
///
/// Stage photos still use StagePhotoPreviewScreen because that screen owns
/// stage-photo deletion. This generic preview is intentionally read-only and is
/// used by expenses and chat image messages.
class FullscreenImagePreviewScreen extends StatelessWidget {
  const FullscreenImagePreviewScreen({
    super.key,
    required this.imageUrl,
    required this.title,
    this.details = const [],
  });

  final String imageUrl;
  final String title;
  final List<String> details;

  @override
  Widget build(BuildContext context) {
    final visibleDetails = details
        .map((detail) => detail.trim())
        .where((detail) => detail.isNotEmpty)
        .toList();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Center(
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.contain,
                  placeholder: (context, _) => const Center(
                    child: CircularProgressIndicator(),
                  ),
                  errorWidget: (context, _, __) => const Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white,
                      size: 48,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (visibleDetails.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(190),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var index = 0;
                            index < visibleDetails.length;
                            index++)
                          Padding(
                            padding: EdgeInsets.only(top: index == 0 ? 0 : 6),
                            child: Text(
                              visibleDetails[index],
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: index == 0
                                    ? FontWeight.w800
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
