import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:grpc/grpc.dart' as grpc;
import 'package:mic_stream/mic_stream.dart';
import 'jarvis_asr/jarvis_asr.pb.dart' as jasr;
import 'jarvis_asr/jarvis_asr.pbgrpc.dart';
import 'audio/audio.pb.dart';

class MicStreamingInputToText extends StatefulWidget {
  @override
  _MicStreamingInputToTextState createState() =>
      _MicStreamingInputToTextState();
}

class _MicStreamingInputToTextState
    extends State<MicStreamingInputToText> {
  String printMsg = 'waiting';
  Stream<List<int>> stream;
  var listener;
  // var requests = [];
  bool isRecording = false;

  var channel;
  var stub;
  var streamingConfig;

  @override
  Widget build(BuildContext context) {
    return Center(
        child: Column(
      children: [
        ElevatedButton(
          child: Text(isRecording ? '녹음 중지' : '녹음 시작'),
          onPressed: () {
            if (isRecording) {
              print('녹음 끝!');
              stopRecording();
            } else {
              print('녹음 시작!');
              startRecording();
            }
          },
        ),
        Text(printMsg),
      ],
    ));
  }

  startRecording() async {
    setState(() {
      printMsg = 'waiting';
    });
    if (isRecording) return;
    setState(() {
      isRecording = true;
    });
    print('started well');

    // Init a new Stream
    stream = await MicStream.microphone(
        sampleRate: 16000, audioFormat: AudioFormat.ENCODING_PCM_16BIT);

    // Init the communication with Jarvis
    channel = grpc.ClientChannel(
      '163.239.28.21',
      port: 50051,
      options: const grpc.ChannelOptions(
          credentials: grpc.ChannelCredentials.insecure()),
    );
    stub = JarvisASRClient(channel);
    var config = RecognitionConfig();
    config.encoding = AudioEncoding.LINEAR_PCM;
    config.sampleRateHertz = 16000;
    config.languageCode = "en-US";
    config.maxAlternatives = 1;
    config.enableAutomaticPunctuation = true;
    config.audioChannelCount = 1;
    streamingConfig =
        jasr.StreamingRecognitionConfig(config: config, interimResults: true);

    var responses =
        stub.streamingRecognize(build_generator(streamingConfig, stream));

    listener = responses.listen((response){
      setState(() {
        if (response.results == false) {
          return;
        }
        try {
          printMsg = response.results[0].alternatives[0].transcript;
        } catch (err) {
          return;
        }
      });
    });
  }

  Stream<StreamingRecognizeRequest> build_generator(cfg, stream) async* {
    yield jasr.StreamingRecognizeRequest(streamingConfig: cfg);
      await for (var content in stream) {
        yield jasr.StreamingRecognizeRequest(audioContent: content);
      }
  }

  stopRecording() async {
    if (!isRecording) return;
    setState(() {
      isRecording = false;
    });

    // Cancel the subscription
    listener.cancel();
    channel.shutdown();

    print('stopped well');
  }

  listen_print_loop(responses, {showIntermediate = false}) async {
    print('lpl');
    String msg = "";
    int num_chars_printed = 0;
    int idx = 0;
    await for (var response in responses) {
      idx += 1;
      if (response.results == false) {
        continue;
      }
      var result;
      try {
        result = response.results[0];
      } catch (err) {
        continue;
      }

      if (result.alternatives == false) {
        continue;
      }
      var transcript = result.alternatives[0].transcript;

      if (showIntermediate == true) {
        var overwrite_chars = ' ' * (num_chars_printed - transcript.length);

        if (result.isFinal == false) {
          num_chars_printed = transcript.length + 3;
        } else {
          msg = transcript + overwrite_chars + "\n";
          num_chars_printed = 0;
        }
      } else {
        if (result.isFinal == true) {
          msg = "${transcript}\n";
        }
      }
    }
    return msg;
  }
}
