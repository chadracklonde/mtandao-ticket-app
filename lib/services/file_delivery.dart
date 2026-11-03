import 'dart:io';
import 'dart:typed_data';

import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

/// Dossier d'enregistrement sur ordinateur : `Documents/Mtandao Ticket`.
String desktopExportDir(Map<String, String> env, {required bool windows}) {
  final home = (windows ? env['USERPROFILE'] : env['HOME']) ?? env['HOME'] ?? env['USERPROFILE'] ?? '.';
  final sep = windows ? '\\' : '/';
  return '$home${sep}Documents${sep}Mtandao Ticket';
}

/// Résultat d'une remise de fichier : chemin si enregistré sur l'ordinateur,
/// null si le menu de partage du téléphone a été utilisé.
typedef DeliveredPath = String?;

/// Remet un fichier à l'utilisateur : menu de partage sur Android/iOS,
/// enregistrement dans `Documents/Mtandao Ticket` puis ouverture sur
/// Windows et macOS.
Future<DeliveredPath> deliverFile(
  Uint8List bytes,
  String filename, {
  required String mimeType,
}) async {
  if (Platform.isAndroid || Platform.isIOS) {
    if (mimeType == 'application/pdf') {
      await Printing.sharePdf(bytes: bytes, filename: filename);
    } else {
      await Share.shareXFiles([XFile.fromData(bytes, name: filename, mimeType: mimeType)]);
    }
    return null;
  }
  final windows = Platform.isWindows;
  final dir = Directory(desktopExportDir(Platform.environment, windows: windows));
  await dir.create(recursive: true);
  final sep = windows ? '\\' : '/';
  final path = '${dir.path}$sep$filename';
  await File(path).writeAsBytes(bytes, flush: true);
  try {
    if (windows) {
      await Process.run('cmd', ['/c', 'start', '', path]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [path]);
    } else {
      await Process.run('xdg-open', [path]);
    }
  } catch (_) {
    // Le fichier est enregistré ; l'ouverture automatique est facultative.
  }
  return path;
}
