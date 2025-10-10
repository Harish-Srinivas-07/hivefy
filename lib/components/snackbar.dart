import 'package:flutter/material.dart';
import 'package:figma_squircle/figma_squircle.dart';
import 'package:toastification/toastification.dart';

enum Severity { error, warning, info, success }

Future<void> info(
  String message,
  Severity severity, {
  Alignment alignment = Alignment.bottomCenter,
}) async {
  IconData iconData;
  Color iconColor;

  switch (severity) {
    case Severity.error:
      iconData = Icons.error;
      iconColor = Colors.red;
      break;
    case Severity.warning:
      iconData = Icons.warning;
      iconColor = Colors.yellow;
      break;
    case Severity.info:
      iconData = Icons.info;
      iconColor = Colors.blue;
      break;
    case Severity.success:
      iconData = Icons.check_circle;
      iconColor = Colors.green;
      break;
  }

  toastification.show(
    title: Text(
      message,
      maxLines: 5,
      overflow: TextOverflow.ellipsis,
      softWrap: true,
      style: TextStyle(fontWeight: FontWeight.w500, color: Colors.white),
      textScaler: const TextScaler.linear(1),
    ),
    borderSide: const BorderSide(color: Colors.white54, width: 0.5),
    borderRadius: SmoothBorderRadius(cornerRadius: 20, cornerSmoothing: 1),
    alignment: alignment,
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
    type: ToastificationType.defaultValues[severity.index],
    style: ToastificationStyle.flat,
    autoCloseDuration: const Duration(seconds: 3),
    applyBlurEffect: true,
    backgroundColor: const Color(0xFF1C1C1C),
    icon: Icon(iconData, size: 25, color: iconColor),
    closeButton: const ToastCloseButton(showType: CloseButtonShowType.none),
    closeOnClick: true,
    dragToClose: true,
  );
}
