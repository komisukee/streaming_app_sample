import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livestreaming_app/rtmp_publisher/camera.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock/wakelock.dart';

class CameraExampleHome extends StatefulWidget {
  @override
  _CameraExampleHomeState createState() {
    return _CameraExampleHomeState();
  }
}

/// カメラの向きに対応したアイコンデータを返す関数
IconData getCameraLensIcon(CameraLensDirection direction) {
  switch (direction) {
    case CameraLensDirection.back:
      return Icons.camera_rear;
    case CameraLensDirection.front:
      return Icons.camera_front;
    case CameraLensDirection.external:
      return Icons.camera;
  }
  throw ArgumentError('Unknown lens direction');
}

void logError(String code, String message) =>
    print('Error: $code\nError Message: $message');

class _CameraExampleHomeState extends State<CameraExampleHome>
    with WidgetsBindingObserver {
  CameraController? controller;
  String? url;
  VideoPlayerController? videoController;
  bool enableAudio = true;
  bool useOpenGL = true;
  Timer? _timer;

  @override
  void initState() {
    //WidgetsBindingObserverの初期化
    super.initState();
    WidgetsBinding.instance?.addObserver(this);
  }

  @override
  void dispose() {
    //WidgetsBindingObserverの破棄
    WidgetsBinding.instance?.removeObserver(this);
    super.dispose();
  }

  @override
  // didChangeAppLifecycleStateを使用してアプリのライフサイクルがどの状態であるかを検出
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (controller == null || !controller!.value.isInitialized) {
      return;
    }
    //アプリは表示されているが、フォーカスがあたっていない状態
    if (state == AppLifecycleState.inactive) {
      controller?.dispose(); //このカメラのリソースを解放.
      if (_timer != null) {
        _timer?.cancel();
        _timer = null;
      }
      //アプリがフォアグランドに遷移し（paused状態から復帰）、復帰処理用の状態
    } else if (state == AppLifecycleState.resumed) {
      //アプリが復帰時（resumed）に処理を実行
      if (controller != null) {
        onNewCameraSelected(controller!.description);
      }
    }
  }

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        key: _scaffoldKey,
        appBar: AppBar(
          title: const Text('live demo app'),
        ),
        body: Column(
          children: <Widget>[
            Expanded(
              child: Container(
                child: Padding(
                  padding: const EdgeInsets.all(1.0),
                  child: Center(child: _cameraPreviewWidget()),
                ),
              ),
            ),
            _streamingButtonWidget(),
            _isStreamingRowWidget(),
            Padding(
              padding: const EdgeInsets.all(5.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: <Widget>[
                  _cameraTogglesRowWidget(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// カメラからのプレビューを表示するためのwidget（プレビューがない場合はメッセージ）。
  Widget _cameraPreviewWidget() {
    if (controller == null || !controller!.value.isInitialized) {
      // カメラの準備ができるまではテキストを表示
      return const Text(
        '下のカメラボタンをタップ',
        style: TextStyle(
          color: Colors.black,
          fontSize: 24.0,
          fontWeight: FontWeight.w900,
        ),
      );
    } else {
      return AspectRatio(
        aspectRatio: controller!.value.aspectRatio,
        child: CameraPreview(controller!),
      );
    }
  }

  /// 視聴開始するためのボタンと終了ボタンを表示するためのwidget
  Widget _streamingButtonWidget() {
    return (controller != null &&
            controller!.value.isInitialized &&
            !controller!.value.isStreamingVideoRtmp)
        ? RaisedButton.icon(
            icon: const Icon(Icons.watch),
            label: Text('配信開始'),
            textColor: Colors.blue,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            onPressed: () {
              if (controller != null &&
                  controller!.value.isInitialized &&
                  !controller!.value.isStreamingVideoRtmp) {
                return onVideoStreamingButtonPressed();
              }
              return null;
            },
          )
        : RaisedButton.icon(
            icon: const Icon(Icons.stop),
            textColor: Colors.red,
            label: Text('配信終了'),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            onPressed: () {
              if (controller != null &&
                  controller!.value.isInitialized &&
                  controller!.value.isStreamingVideoRtmp) {
                return onStopButtonPressed();
              }
              return null;
            });
  }

  //配信しているかどうかをテキストで表示するためのwidget
  Widget _isStreamingRowWidget() {
    return (controller != null &&
            controller!.value.isInitialized &&
            controller!.value.isStreamingVideoRtmp)
        ? Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: CircularProgressIndicator(),
              ),
              Text("配信中",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
            ],
          )
        :
        //配信中でない場合にテキストを表示
        Text("配信していません。",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20));
  }

  // カメラのインアウトを切り替えるトグルWidget
  Widget _cameraTogglesRowWidget() {
    final List<Widget> toggles = <Widget>[];

    if (cameras.isEmpty) {
      return const Text('No camera found');
    } else {
      for (CameraDescription cameraDescription in cameras) {
        print(cameraDescription);
        toggles.add(
          SizedBox(
            width: 90.0,
            child: RadioListTile<CameraDescription>(
              title: Icon(getCameraLensIcon(cameraDescription.lensDirection)),
              groupValue: controller?.description,
              value: cameraDescription,
              onChanged: (cameraDescription) =>
                  onNewCameraSelected(cameraDescription!),
            ),
          ),
        );
      }
    }
    return Row(children: toggles);
  }

  //snackbarを表示するための関数
  void showInSnackBar(String message) {
    _scaffoldKey.currentState?.showSnackBar(SnackBar(content: Text(message)));
  }

  // トグルが選択された時に呼ばれるコールバック関数
  void onNewCameraSelected(CameraDescription cameraDescription) async {
    if (controller != null) {
      await controller!.dispose();
    }
    controller = CameraController(
      cameraDescription,
      ResolutionPreset.medium,
      enableAudio: enableAudio,
      androidUseOpenGL: useOpenGL,
    );
    // トグルにおうじて、カメラのUIを更新
    controller!.addListener(() {
      if (mounted) setState(() {});
      if (controller!.value.hasError) {
        showInSnackBar('Camera error ${controller!.value.errorDescription}');
        if (_timer != null) {
          _timer?.cancel();
          _timer = null;
        }
        Wakelock.disable();
      }
    });

    try {
      await controller!.initialize();
    } on CameraException catch (e) {
      _showCameraException(e);
    }

    if (mounted) {
      setState(() {});
    }
  }

  //配信スタートボタンをおされたときに呼ばれす関数
  void onVideoStreamingButtonPressed() {
    startVideoStreaming().then((String? url) {
      if (mounted) setState(() {});
      if (url != null) {
        showInSnackBar('配信を開始します。 $url');
      }
      Wakelock.enable();
    });
  }

  //配信ストップボタンをおされたときに呼ばれす関数
  void onStopButtonPressed() {
    if (controller!.value.isStreamingVideoRtmp) {
      stopVideoStreaming().then((_) {
        if (mounted) setState(() {});
        showInSnackBar('配信終了しました。: $url');
      });
    }
    Wakelock.disable();
  }

  //配信を開始するための関数
  Future<String?> startVideoStreaming() async {
    if (!controller!.value.isInitialized) {
      showInSnackBar('Error: select a camera first.');
      return null;
    }
    //配信中であればnullを返す（
    if (controller!.value.isStreamingVideoRtmp) {
      return null;
    }

    // rtmpURLを指定を(自由に変更してください)
    String rtmpUrl = 'rtmp://localhost:1935/live/test';
    try {
      if (_timer != null) {
        _timer?.cancel();
        _timer = null;
      }
      url = rtmpUrl;
      await controller!.startVideoStreaming(url!);
      _timer = Timer.periodic(Duration(seconds: 1), (timer) async {
        var stats = await controller!.getStreamStatistics();
        print(stats);
      });
    } on CameraException catch (e) {
      _showCameraException(e);
      return null;
    }
    return rtmpUrl;
  }

  //配信を終了するための関数
  Future<void> stopVideoStreaming() async {
    if (!controller!.value.isStreamingVideoRtmp) {
      //配信中でなければnullを返す
      return;
    }

    try {
      await controller!.stopVideoStreaming();
      if (_timer != null) {
        _timer?.cancel();
        _timer = null;
      }
    } on CameraException catch (e) {
      _showCameraException(e);
      return;
    }
  }

  void _showCameraException(CameraException e) {
    logError(e.code, e.description);
    showInSnackBar('Error: ${e.code}\n${e.description}');
  }
}

class CameraApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: CameraExampleHome(),
    );
  }
}

List<CameraDescription> cameras = [];

Future<void> main() async {
  // エントリーポイント
  try {
    //Flutter Engineの機能を利用したい場合にコールする
    //Flutter Engineの機能とは、Android, iOSなどの画面の向きの設定やロケールなど
    WidgetsFlutterBinding.ensureInitialized();
    cameras = await availableCameras();
  } on CameraException catch (e) {
    logError(e.code, e.description);
  }
  runApp(CameraApp());
}
