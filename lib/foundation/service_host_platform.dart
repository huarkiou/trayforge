/// Picks the [ServiceHost] adapter for the current platform.
library;

import 'dart:io';

import 'package:trayforge/foundation/service_host.dart';
import 'package:trayforge/foundation/service_host_linux.dart';
import 'package:trayforge/foundation/service_host_win32.dart';

ServiceHost createServiceHost() {
  if (Platform.isWindows) return const Win32ServiceHost();
  if (Platform.isLinux) return LinuxServiceHost();
  return const UnsupportedServiceHost();
}
