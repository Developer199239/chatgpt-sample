import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';

void viewImage(BuildContext context, String image) {
  showDialog(
    useSafeArea: true,
    context: context,
    builder: (context) {
      if (image.isNotEmpty) {
        return Center(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * .50,
            width: MediaQuery.of(context).size.width,
            child: PhotoView(
              imageProvider: CachedNetworkImageProvider(image),
            ),
          ),
        );
      } else {
        return const SizedBox.shrink();
      }
    },
  );
}
