import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Stands in for the camera in widget tests: [show] "points the camera" at a
/// barcode by pushing it into the stream MobileScanner listens to.
class FakeScannerPlatform extends MobileScannerPlatform {
  final StreamController<BarcodeCapture?> barcodes = StreamController.broadcast();

  void show(String value) => barcodes.add(BarcodeCapture(barcodes: [Barcode(rawValue: value)]));

  @override
  Stream<BarcodeCapture?> get barcodesStream => barcodes.stream;
  @override
  Stream<TorchState> get torchStateStream => const Stream.empty();
  @override
  Stream<double> get zoomScaleStateStream => const Stream.empty();
  @override
  Widget buildCameraView() => const ColoredBox(color: Colors.black);
  @override
  Future<MobileScannerViewAttributes> start(StartOptions startOptions) async => const MobileScannerViewAttributes(
        cameraDirection: CameraFacing.back,
        currentTorchMode: TorchState.off,
        size: Size(1280, 720),
      );
  @override
  Future<void> stop() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> toggleTorch() async {}
  @override
  Future<void> setZoomScale(double zoomScale) async {}
  @override
  Future<void> resetZoomScale() async {}
  @override
  Future<void> setFocusPoint(Offset position) async {}
  @override
  Future<void> updateScanWindow(Rect? window) async {}
  @override
  Future<void> dispose() async {}
}
