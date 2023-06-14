import 'dart:async';

import 'package:aichat/stores/AIChatStore.dart';
import 'package:aichat/utils/Chatgpt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

GlobalKey<_QuestionInputState> globalQuestionInputKey = GlobalKey();

class QuestionInput extends StatefulWidget {
  final Map chat;
  final bool autofocus;
  final bool enabled;
  final Function? scrollToBottom;
  final Function? onGeneratingStatusChange;

  const QuestionInput({
    Key? key,
    required this.chat,
    required this.autofocus,
    required this.enabled,
    this.scrollToBottom,
    this.onGeneratingStatusChange,
  }) : super(key: key);

  @override
  _QuestionInputState createState() => _QuestionInputState();
}

class _QuestionInputState extends State<QuestionInput> {
  final FocusNode focusNode = FocusNode();
  TextEditingController questionController = TextEditingController();
  bool _isGenerating = false;
  String myQuestion = '';

  final SpeechToText speechToText = SpeechToText();
  final FlutterTts flutterTts = FlutterTts();
  String lastWords = '';
  int start = 200;
  int delay = 200;
  bool isListening = false;
  Timer? stopListeningTimer;
  int selectedRadio = 0;

  @override
  void initState() {
    super.initState();
    initSpeechToText();
    initTextToSpeech();
  }

  Future<void> initTextToSpeech() async {
    await flutterTts.setSharedInstance(true);
    setState(() {});
  }

  Future<void> initSpeechToText() async {
    await speechToText.initialize();
    setState(() {});
  }

  Future<void> startListening() async {
    await speechToText.listen(
      onResult: onSpeechResult,
      listenFor: Duration(seconds: 60), // Adjust the duration as needed
    );
    setState(() {
      isListening = true;
    });
    // Start the timer to stop listening if not stopped automatically
    stopListeningTimer = Timer(Duration(seconds: 3), stopListening);
  }

  Future<void> stopListening() async {
    await speechToText.stop();
    setState(() {
      isListening = false;
    });
    // Cancel the timer if it's still active
    stopListeningTimer?.cancel();
    // Call the callback function
    onSpeechDone();
  }

  void onSpeechDone() {
    // Code to be executed when speech recognition is finished
    print('Speech recognition finished!');
    // Add any desired functionality here
    onSubmit();
  }

  void onSpeechResult(SpeechRecognitionResult result) {
    setState(() {
      lastWords = result.recognizedWords;
    });
    // Reset the timer on each speech result
    stopListeningTimer?.cancel();
    stopListeningTimer = Timer(Duration(seconds: 3), stopListening);
  }

  Future<void> systemSpeak(String content) async {
    await flutterTts.speak(content);
  }

  @override
  void dispose() {
    questionController.dispose();
    speechToText.stop();
    flutterTts.stop();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    precacheImage(
      const AssetImage('images/submit_active_icon.png'),
      context,
    );
    super.didChangeDependencies();
  }

  void _updateGeneratingStatus(bool value) {
    _isGenerating = value;

    if (widget.onGeneratingStatusChange != null) {
      widget.onGeneratingStatusChange!(value);
    }

    setState(() {});
  }

  void reGenerate(int messageIndex) async {
    _updateGeneratingStatus(true);
    final store = Provider.of<AIChatStore>(context, listen: false);
    Map chat = widget.chat;
    List messages = [];
    Map ai = chat['ai'];

    /// If it is a continuous conversation, check whether it is related
    if (ai['isContinuous']) {
      messages = [
        chat['systemMessage'],
        ...chat['messages'].take(messageIndex),
      ];
    } else {
      messages = [
        chat['systemMessage'],
        chat['messages'][messageIndex],
      ];
    }

    /// This is the state in formation
    await store.replaceMessage(chat['id'], messageIndex, {
      'role': 'generating',
      'content': '',
    });
    try {
      // void onProgress(chatStreamEvent) {
      //   final firstCompletionChoice = chatStreamEvent.choices.first;
      //   if (firstCompletionChoice.finishReason == 'stop') {
      //     _updateGeneratingStatus(false);
      //     return;
      //   }
      //   store.pushStreamMessage(chat['id'], messageIndex, {
      //     'role': 'assistant',
      //     'content': firstCompletionChoice.delta.content,
      //   });
      // }
      //
      // ChatGPT.sendMessageOnStream(
      //   messages,
      //   onProgress: onProgress,
      // );
      final response = await ChatGPT.sendMessage(messages);
      final firstCompletionChoice = response.choices.first;
      await store.replaceMessage(chat['id'], messageIndex, {
        'role': 'assistant',
        'content': firstCompletionChoice.message.content,
      });

      _updateGeneratingStatus(false);
    } catch (error) {
      print(error);
      _updateGeneratingStatus(false);
      await store.replaceMessage(chat['id'], messageIndex, {
        'role': 'error',
        'content': error.toString(),
      });
    }

    print(messages);
  }

  void onSubmit() async {
    final store = Provider.of<AIChatStore>(context, listen: false);
    if (myQuestion == '' && lastWords == '') {
      return;
    }
    if (_isGenerating) {
      print('---_isGenerating---');
      return;
    }

    final text = myQuestion.isEmpty ? lastWords : myQuestion;

    lastWords = '';
    _updateGeneratingStatus(true);

    setState(() {
      questionController.clear();
      myQuestion = '';
    });

    Map message = {
      'role': 'user',
      'content': text,
    };

    bool isFirstMessage = widget.chat['messages'].length == 0;
    Map chat = await store.pushMessage(widget.chat, message);

    List messages = [
      chat['systemMessage'],
      message,
    ];
    Map ai = chat['ai'];

    /// If it is a continuous conversation, check whether it is related
    if (!isFirstMessage && ai['isContinuous']) {
      messages = [
        chat['systemMessage'],
        ...chat['messages'],
      ];
    }

    /// This is the state in formation
    Map generatingChat = await store.pushMessage(widget.chat, {
      'role': 'generating',
      'content': '',
    });
    int messageIndex = generatingChat['messages'].length - 1;
    if (widget.scrollToBottom != null) {
      widget.scrollToBottom!();
    }
    try {
      final response = await ChatGPT.sendMessage(messages);
      final firstCompletionChoice = response.choices.first;
      await store.replaceMessage(chat['id'], messageIndex, {
        'role': 'assistant',
        'content': firstCompletionChoice.message.content,
      });
      _updateGeneratingStatus(false);
    } catch (error) {
      print(error);
      _updateGeneratingStatus(false);
      await store.replaceMessage(chat['id'], messageIndex, {
        'role': 'error',
        'content': error.toString(),
      });
      if (widget.scrollToBottom != null) {
        widget.scrollToBottom!();
      }
    }
  }

  void onQuestionChange(String value) {
    setState(() {
      myQuestion = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: MediaQuery.of(context).size.width,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(
            width: 0.5,
            color: Color.fromRGBO(210, 210, 210, 1.0),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 4, 8, 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(50.0),
                border: Border.all(color: Colors.grey),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      focusNode: focusNode,
                      enabled: widget.enabled,
                      controller: questionController,
                      minLines: 1,
                      maxLines: 2,
                      decoration: const InputDecoration.collapsed(
                        hintText: 'Enter your message',
                      ),
                      autofocus: widget.autofocus,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 18,
                        height: 24 / 18,
                        textBaseline: TextBaseline.alphabetic,
                      ),
                      onChanged: onQuestionChange,
                      textInputAction: TextInputAction.search,
                      textCapitalization: TextCapitalization.words,
                      enableInteractiveSelection: true,
                      onSubmitted: (String value) {
                        onSubmit();
                      },
                      onTap: () {
                        if (widget.scrollToBottom != null) {
                          widget.scrollToBottom!();
                        }
                      },
                    ),
                  ),
                  widget.enabled
                      ? renderSubmitBtnWidget()
                      : IgnorePointer(
                          child: renderSubmitBtnWidget(),
                        ),
                ],
              ),
            ),
          ),
          const SizedBox(
            width: 20,
          ),
          InkWell(
            onTap: widget.enabled
                ? () async {
                    if (await speechToText.hasPermission &&
                        speechToText.isNotListening) {
                      await startListening();
                    } else if (speechToText.isListening) {
                      await stopListening();
                    } else {
                      initSpeechToText();
                    }
                  }
                : null,
            child: Icon(
              speechToText.isListening ? Icons.stop : Icons.mic,
            ),
          ),
        ],
      ),
    );
  }

  Widget renderSubmitBtnWidget() {
    bool isActive = myQuestion != '' && !_isGenerating;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        onSubmit();
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
        width: 50,
        child: Image(
          image: AssetImage(
              'images/${isActive ? 'submit_active_icon' : 'submit_icon'}.png'),
        ),
      ),
    );
  }
}
