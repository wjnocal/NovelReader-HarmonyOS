// System dark mode affects presentation only; keep the user's saved reading theme intact.
export class AppTheme {
  static readerBackground(themeMode: number, systemDarkMode: boolean): string {
    if (systemDarkMode) return '#000000';
    switch (themeMode) {
      case 1: return '#E7E1CF';
      case 2: return '#DDE8DD';
      case 3: return '#1D211F';
      default: return '#F7F4ED';
    }
  }

  static readerTextColor(themeMode: number, systemDarkMode: boolean): string {
    return systemDarkMode || themeMode === 3 ? '#D7D9D7' : '#282A27';
  }

  static readerSecondaryTextColor(themeMode: number, systemDarkMode: boolean): string {
    return systemDarkMode || themeMode === 3 ? '#A7ABA8' : '#687169';
  }

  static readerBarBackground(themeMode: number, systemDarkMode: boolean): string {
    if (systemDarkMode) return '#F0181818';
    return themeMode === 3 ? '#F0242826' : '#F7F4ED';
  }
}
