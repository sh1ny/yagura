import '../files/files.dart';

/// Creates the directory link of a staged mod: [path] below the instance root
/// of [fs] becomes a junction to the content-store directory [target]. The
/// daemon's own is `fs.createJunction`; a test replaces it to model a volume
/// that cannot hold links (`stage_link_failed`).
typedef StageLinkCreator = void Function(
  InstanceFs fs,
  String path,
  String target,
);

void defaultStageLink(InstanceFs fs, String path, String target) =>
    fs.createJunction(path, target);
