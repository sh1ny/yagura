import '../operations/operation_runner.dart';
import '../operations/prompt_broker.dart';
import 'steam_service.dart';

/// Maps a Steam run's reports to the events of the operation it runs for: step
/// and progress events, log lines, warnings, and the prompts a login raises.
class OperationSteamReporter implements SteamRunReporter {
  OperationSteamReporter(this._ctx);

  final OperationContext _ctx;
  var _step = '';

  @override
  void step(String name) {
    _step = name;
    _ctx.beginStep(name);
  }

  @override
  void progress({double percent = -1, int bytesDone = 0, int bytesTotal = 0}) =>
      _ctx.progress(
        _step,
        percent: percent,
        bytesDone: bytesDone,
        bytesTotal: bytesTotal,
      );

  @override
  void log(String text) => _ctx.log(text);

  @override
  void warn(String warning) => _ctx.warn(warning);

  @override
  PromptTicket prompt(PromptSpec spec) => _ctx.raisePrompt(spec);
}
