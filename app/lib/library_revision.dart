import 'package:flutter/foundation.dart';

/// 书架在导入、删除和播完一章后变一次；剧本库和试镜页据此刷新。
final ValueNotifier<int> libraryRevision = ValueNotifier<int>(0);

void bumpLibraryRevision() {
  libraryRevision.value++;
}
