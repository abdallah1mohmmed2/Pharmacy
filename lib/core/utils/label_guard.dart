// lib/core/utils/label_guard.dart
class LabelGuard {
 LabelGuard._();
 static final RegExp _forbidden=RegExp('(?:مدين|دائن)',caseSensitive:false);
 static bool containsForbidden(String value)=>_forbidden.hasMatch(value);
 static List<String> findForbidden(String value)=>_forbidden.allMatches(value).map((m)=>m.group(0)!).toList(growable:false);
 static String sanitize(String value,{String replacement='رصيد'})=>value.replaceAll(_forbidden,replacement);
 static void assertClean(String value,{String? context}) {
  if(containsForbidden(value)) throw FormatException('مصطلح محظور في '+(context??'النص')+': '+findForbidden(value).join('، '));
 }
}
