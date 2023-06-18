import 'dart:io';

import 'package:aichat/components/QuestionInput.dart';
import 'package:aichat/stores/AIChatStore.dart';
import 'package:aichat/utils/Chatgpt.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:lottie/lottie.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:share/share.dart';

import '../utils/constants.dart';

class ChatPage extends StatefulWidget {
  final String chatId;
  final bool autofocus;
  final String chatType;

  const ChatPage({
    Key? key,
    required this.chatId,
    required this.autofocus,
    required this.chatType,
  }) : super(key: key);

  @override
  _ChatPageState createState() => _ChatPageState();
}

enum TtsState { playing, stopped, paused, continued }

class _ChatPageState extends State<ChatPage> {
  static final LottieBuilder _generatingLottie =
      Lottie.asset("images/loading2.json");

  final ScrollController _listController = ScrollController();

  late FlutterTts _flutterTts;
  TtsState _ttsState = TtsState.stopped;
  String _speakText = '';

  bool _isCopying = false;
  bool _isImage = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  Future<void> initTts() async {
    _flutterTts = FlutterTts();

    _setAwaitOptions();

    _flutterTts.setStartHandler(() {
      setState(() {
        print("Playing");
        _ttsState = TtsState.playing;
      });
    });

    _flutterTts.setCompletionHandler(() {
      setState(() {
        print("Complete");
        _ttsState = TtsState.stopped;
      });
    });

    _flutterTts.setCancelHandler(() {
      setState(() {
        print("Cancel");
        _ttsState = TtsState.stopped;
      });
    });

    _flutterTts.setPauseHandler(() {
      setState(() {
        print("Paused");
        _ttsState = TtsState.paused;
      });
    });

    _flutterTts.setContinueHandler(() {
      setState(() {
        print("Continued");
        _ttsState = TtsState.continued;
      });
    });

    _flutterTts.setErrorHandler((msg) {
      setState(() {
        print("error: $msg");
        _ttsState = TtsState.stopped;
      });
    });
  }

  Future _setAwaitOptions() async {
    await _flutterTts.awaitSpeakCompletion(true);
  }

  Future<void> _speak(String text) async {
    // 如果正在播放，则先停止
    if (_ttsState == TtsState.playing) {
      await _flutterTts.stop();
    }
    if (_speakText == text) {
      _speakText = '';
      return;
    }
    _speakText = text;
    await _flutterTts.speak(text);
  }

  @override
  void initState() {
    super.initState();

    initTts();

    // WidgetsBinding.instance.addPostFrameCallback((mag) {
    // print("页面渲染完毕");
    // scrollToBottom();
    // });
  }

  @override
  void dispose() {
    _flutterTts.stop();
    super.dispose();
  }

  void scrollToBottom() {
    // _listController.animateTo(
    //   _listController.position.maxScrollExtent,
    //   duration: const Duration(milliseconds: 500),
    //   curve: Curves.easeInOut,
    // );
    if (_listController.hasClients) {
      _listController.jumpTo(_listController.position.maxScrollExtent);
    }
  }

  void _showToastMsg(String msg) {
    Fluttertoast.showToast(
      msg: msg,
      toastLength:
          Toast.LENGTH_SHORT, // Duration for which the toast is visible
      gravity: ToastGravity.BOTTOM, // Position of the toast on the screen
      backgroundColor: Colors.grey[700], // Background color of the toast
      textColor: Colors.white, // Text color of the toast
      fontSize: 16.0, // Font size of the toast message
    );
  }

  void _checkFileDownloadPermission(String url) async {
    PermissionStatus status = await Permission.storage.status;
    if (status.isGranted) {
      _downloadImage(url);
    } else {
      PermissionStatus requestStatus = await Permission.storage.request();
      if (requestStatus.isGranted) {
        _downloadImage(url);
      } else {
        _showToastMsg("Permission denied");
      }
    }
  }

  void _downloadImage(String imageUrl) async {
    try {
      final cacheManager = DefaultCacheManager();
      final fileInfo = await cacheManager.getFileFromCache(imageUrl);

      final appDir = await getTemporaryDirectory();
      final file = File('${appDir.path}/ai_generated_image.jpg');
      await fileInfo?.file.copy(file.path);

      final result = await ImageGallerySaver.saveFile(file.path);
      if (result['isSuccess']) {
        await file.delete(); // Remove the temporary file
        _showToastMsg('Image saved to gallery');
      } else {
        _showToastMsg('Failed to save image: ${result['errorMessage']}');
      }
    } catch (e) {
      _showToastMsg('Error: $e');
    }
  }

  void share(String imageUrl) async {
    try {
      final cacheManager = DefaultCacheManager();
      final fileInfo = await cacheManager.getFileFromCache(imageUrl);

      final appDir = await getTemporaryDirectory();
      final file = File('${appDir.path}/ai_generated_image.jpg');
      await fileInfo?.file.copy(file.path);

      Share.shareFiles([file.path], text: 'Check out this image!');
    } catch (e) {
      print('Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = Provider.of<AIChatStore>(context, listen: true);
    final chat = store.getChatById(widget.chatType, widget.chatId);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        systemOverlayStyle: SystemUiOverlayStyle.light,
        toolbarHeight: 60,
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        title: Row(
          children: [
            InkWell(
              splashColor: Colors.white,
              highlightColor: Colors.white,
              onTap: () {
                Navigator.pop(context);
              },
              child: Row(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        height: 60,
                        child: Row(
                          children: const [
                            SizedBox(width: 24),
                            Image(
                              width: 18,
                              image: AssetImage('images/back_icon.png'),
                            ),
                            SizedBox(width: 12),
                            Text(
                              "ChatGPT",
                              style: TextStyle(
                                color: Color.fromRGBO(0, 0, 0, 1),
                                fontSize: 18,
                                height: 1,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(width: 24),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            )
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
        actions: const [
          SizedBox(width: 20),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _renderMessageListWidget(
                chat['messages'],
              ),
            ),
            QuestionInput(
              key: globalQuestionInputKey,
              chat: chat,
              autofocus: widget.autofocus,
              enabled: true,
              scrollToBottom: () {
                Future.delayed(const Duration(milliseconds: 300), () {
                  scrollToBottom();
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _renderMessageListWidget(List messages) {
    if (messages.isEmpty) {
      Map aiData = ChatGPT.getAiInfoByType(widget.chatType);

      List<Widget> tipsWidget = [];
      for (int i = 0; i < aiData['tips'].length; i++) {
        String tip = aiData['tips'][i];
        tipsWidget.add(
          Ink(
            decoration: BoxDecoration(
              color: const Color.fromRGBO(229, 245, 244, 1),
              borderRadius: BorderRadius.circular(12.0),
            ),
            child: InkWell(
              splashColor: Colors.transparent,
              highlightColor: const Color.fromRGBO(192, 238, 221, 1.0),
              borderRadius: BorderRadius.circular(12.0),
              onTap: () {
                if (globalQuestionInputKey.currentState != null) {
                  final currentState = globalQuestionInputKey.currentState;
                  if (currentState != null) {
                    currentState.myQuestion = tip;
                    currentState.questionController.clear();
                    currentState.questionController.text = tip;
                    currentState.focusNode.requestFocus();
                    currentState.questionController.selection =
                        TextSelection.fromPosition(
                            TextPosition(offset: tip.length));
                    setState(() {});
                  }
                }
              },
              child: Container(
                width: MediaQuery.of(context).size.width - 120,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Text(
                  tip,
                  softWrap: true,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color.fromRGBO(114, 114, 114, 1.0),
                    fontSize: 14,
                    height: 20 / 14,
                  ),
                ),
              ),
            ),
          ),
        );
        tipsWidget.add(
          const SizedBox(height: 10),
        );
      }
      return SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 60),
            const Image(
              width: 18,
              height: 18,
              image: AssetImage('images/tip_icon.png'),
            ),
            const SizedBox(height: 12),
            const Text(
              'Tip',
              style: TextStyle(
                color: Colors.black,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 12),
            Column(
              children: tipsWidget,
            ),
            const SizedBox(height: 60),
          ],
        ),
      );
    }

    return _genMessageListWidget(messages);
  }

  /// TODO Performance optimization?
  Widget _genMessageListWidget(List messages) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 20),
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: false,
      controller: _listController,
      reverse: false,
      itemCount: messages.length,
      itemBuilder: (BuildContext context, int index) {
        return _genMessageItemWidget(messages[index], index);
      },
    );
  }

  Widget _genMessageItemWidget(Map message, int index) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: _renderMessageItem(message, index),
    );
  }

  Widget _renderMessageItem(Map message, int index) {
    _isImage = false;
    String role = message['role'];
    String content = message['content'];
    String defaultAvatar = 'images/logo.png';
    String defaultRoleName = 'ChatGPT';
    Color defaultColor = const Color.fromRGBO(229, 245, 244, 1);
    Color defaultTextColor = Colors.black;
    String defaultTextPrefix = '';
    List<Widget> defaultIcons = [
      _renderVoiceWidget(message),
      const SizedBox(width: 6),
      _renderShareWidget(message),
      const SizedBox(width: 8),
      _renderCopyWidget(message),
    ];
    Widget? customContent;

    if (role == 'user') {
      defaultAvatar = 'images/user_icon.png';
      defaultRoleName = 'You';
      defaultColor = const Color.fromRGBO(236, 236, 236, 1.0);
      defaultIcons = [];
    } else if (role == 'error') {
      defaultTextColor = const Color.fromRGBO(238, 56, 56, 1.0);
      defaultTextPrefix = 'Error:  ';
      defaultIcons = [
        _renderRegenerateWidget(index),
      ];
    } else if (role == 'generating') {
      defaultIcons = [];
      customContent = Row(
        children: [
          SizedBox(
            height: 60,
            child: _generatingLottie,
          )
        ],
      );
    } else if (role == 'assistant' && content.contains('https')) {
      defaultIcons = [
        _renderDownloadWidget(content),
      ];
      _isImage = true;
    }
    return Container(
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
      decoration: BoxDecoration(
        color: defaultColor,
        borderRadius: BorderRadius.circular(16.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(30.0),
                      clipBehavior: Clip.antiAlias,
                      child: Image(
                        width: 36,
                        height: 36,
                        image: AssetImage(defaultAvatar),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      defaultRoleName,
                      softWrap: true,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 16,
                        height: 24 / 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: defaultIcons,
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(
            height: 2,
            color: Color.fromRGBO(124, 119, 119, 1.0),
          ),
          const SizedBox(height: 10),
          Visibility(
            visible: !_isImage,
            child: customContent ??
                MarkdownBody(
                  data: '$defaultTextPrefix${message['content']}',
                  // data: 'This is a line\nThis is another line'.replaceAll('\n', '<br>'),
                  shrinkWrap: true,
                  selectable: true,
                  styleSheet: MarkdownStyleSheet(
                    textScaleFactor: 1.1,
                    textAlign: WrapAlignment.start,
                    p: TextStyle(
                      height: 1.5,
                      color: defaultTextColor,
                    ),
                  ),
                ),
          ),
          Visibility(
              visible: !!_isImage,
              child: Container(
                height: 250,
                width: 250,
                padding: const EdgeInsets.all(0),
                margin: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor,
                  borderRadius: receiverBorder,
                ),
                child: GestureDetector(
                    // onTap: () => viewImage(context, content),
                    onTap: () => {
                          // saveImage(content)
                          share(content)
                        },
                    child: CachedNetworkImage(
                      imageUrl: content,
                      fit: BoxFit.cover,
                      maxHeightDiskCache: 250,
                      progressIndicatorBuilder:
                          (context, url, downloadProgress) => Center(
                              child: CircularProgressIndicator(
                        value: downloadProgress.progress,
                        color: Colors.white,
                      )),
                      errorWidget: (context, url, error) =>
                          const Icon(Icons.error),
                    )),
              )),
        ],
      ),
    );
  }

  Widget _renderShareWidget(Map message) {
    return GestureDetector(
      onTap: () async {
        Share.share(message['content']);
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(2, 2, 2, 2),
        child: const Image(
          image: AssetImage('images/share_message_icon.png'),
          width: 22,
        ),
      ),
    );
  }

  Widget _renderDownloadWidget(String url) {
    return GestureDetector(
      onTap: () async {
        _checkFileDownloadPermission(url);
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(2, 2, 2, 2),
        child: const Image(
          image: AssetImage('images/ic_download.png'),
          width: 26,
        ),
      ),
    );
  }

  Widget _renderVoiceWidget(Map message) {
    return GestureDetector(
      onTap: () async {
        _speak(message['content']);
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(2, 2, 2, 2),
        child: const Image(
          image: AssetImage('images/voice_icon.png'),
          width: 26,
        ),
      ),
    );
  }

  Widget _renderCopyWidget(Map message) {
    return GestureDetector(
      onTap: () async {
        if (_isCopying) {
          return;
        }
        _isCopying = true;
        await Clipboard.setData(
          ClipboardData(
            text: message['content'],
          ),
        );
        EasyLoading.showToast(
          'Copy successfully!',
          dismissOnTap: true,
        );
        _isCopying = false;
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(2, 2, 2, 2),
        child: const Image(
          image: AssetImage('images/chat_copy_icon.png'),
          width: 26,
        ),
      ),
    );
  }

  Widget _renderRegenerateWidget(int index) {
    return GestureDetector(
      onTap: () {
        globalQuestionInputKey.currentState?.reGenerate(index);
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 2, 8, 2),
        child: const Image(
          image: AssetImage('images/refresh_icon.png'),
          width: 26,
        ),
      ),
    );
  }
}
