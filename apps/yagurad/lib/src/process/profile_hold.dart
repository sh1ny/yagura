/// Keeps an account's profile, and with it the account's registry hive,
/// loaded while anything that needs it holds a reference (design D7).
///
/// The launcher unloads its own profile load once the relay has started, but
/// the relay starts the server after that: a process of an account whose hive
/// is not loaded cannot use `HKEY_CURRENT_USER` (Valheim then cannot save on a
/// stop). The service-mode process host takes a reference before each launch
/// and one for every server it supervises, and gives a server's back only when
/// the server has ended.
class ProfileHold {
  ProfileHold(this._load);

  /// Loads the profile and returns what unloads it. Throws when the profile
  /// cannot be loaded (a `LogonFailure` for the real account).
  final void Function() Function() _load;

  var _references = 0;
  void Function()? _unload;

  /// How many holders there are.
  int get references => _references;

  /// Whether this hold has the profile loaded.
  bool get loaded => _unload != null;

  /// Takes a reference, loading the profile for the first. A load that
  /// throws takes none.
  void retain() {
    if (_references == 0) _unload = _load();
    _references++;
  }

  /// Gives a reference back, unloading the profile with the last. Without a
  /// reference held it does nothing.
  void release() {
    if (_references == 0) return;
    _references--;
    if (_references > 0) return;
    final unload = _unload;
    _unload = null;
    unload?.call();
  }
}
