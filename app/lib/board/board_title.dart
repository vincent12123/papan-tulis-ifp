/// Default board title from the creation time, shown in WIB (SPEC §4.1,
/// NFR-04). Asia/Jakarta has no daylight saving, so a fixed +7 is exact.
String defaultBoardTitle(DateTime createdUtc) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];
  final wib = createdUtc.toUtc().add(const Duration(hours: 7));
  String two(int v) => v.toString().padLeft(2, '0');
  return 'Papan ${wib.day} ${months[wib.month - 1]} ${wib.year} '
      '${two(wib.hour)}.${two(wib.minute)}';
}
