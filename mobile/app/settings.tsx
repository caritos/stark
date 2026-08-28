import { View, Text, TouchableOpacity, ScrollView, StyleSheet, Alert, Share, Linking } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import * as FileSystem from 'expo-file-system';
import * as DocumentPicker from 'expo-document-picker';
import Constants from 'expo-constants';
import { parseLine, serializeTasks } from '@shared/parser';
import { useTasks } from '../src/context/TaskContext';
import { writeTasks, resolveFile } from '../src/store';
import { Colors, Fonts, Spacing } from '../src/theme';

const appName = Constants.expoConfig?.name ?? 'Stark';
const appVersion = Constants.expoConfig?.version ?? '';
const buildNumber = Constants.expoConfig?.ios?.buildNumber ?? '';

export default function SettingsScreen() {
  const { storageInfo, pickICloudFolder, finalizeICloud, disableICloud, tasks, reload, weekStart, setWeekStart } = useTasks();
  const insets = useSafeAreaInsets();

  async function handleExport() {
    try {
      const fileUri = FileSystem.cacheDirectory + 'todo.txt';
      await FileSystem.writeAsStringAsync(fileUri, serializeTasks(tasks), { encoding: 'utf8' });
      await Share.share({ url: fileUri, title: 'todo.txt' });
    } catch (e) {
      Alert.alert('Export failed', (e as Error).message);
    }
  }

  async function handleImport() {
    const result = await DocumentPicker.getDocumentAsync({
      type: ['text/plain', 'public.plain-text', '*/*'],
      copyToCacheDirectory: true,
    });
    if (result.canceled || !result.assets?.[0]) return;

    let content: string;
    try {
      content = await FileSystem.readAsStringAsync(result.assets[0].uri, { encoding: 'utf8' });
    } catch (e) {
      Alert.alert('Import failed', (e as Error).message);
      return;
    }

    Alert.alert(
      'Replace all local tasks?',
      `This replaces everything currently on this device with the contents of "${result.assets[0].name}". This cannot be undone.`,
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Replace',
          style: 'destructive',
          onPress: async () => {
            try {
              const parsed = content
                .split('\n')
                .filter(line => line.trim().length > 0)
                .map((line, i) => parseLine(line, i + 1));
              const path = await resolveFile();
              await writeTasks(path, parsed);
              await reload();
              Alert.alert('Imported', `${parsed.length} tasks loaded.`);
            } catch (e) {
              Alert.alert('Import failed', (e as Error).message);
            }
          },
        },
      ]
    );
  }

  async function handleUseICloud() {
    let picked: Awaited<ReturnType<typeof pickICloudFolder>>;
    try {
      picked = await pickICloudFolder();
    } catch (e) {
      const code = (e as { code?: string }).code;
      if (code === 'CANCELLED') return;
      Alert.alert('Could not enable iCloud Drive', (e as Error).message);
      return;
    }

    const { folderBookmark, name, existingTasks } = picked;

    const finalize = async (overwrite: boolean) => {
      try {
        await finalizeICloud(folderBookmark, name, overwrite);
        Alert.alert('iCloud Drive enabled', `Tasks are now stored in "${name}".`);
      } catch (e) {
        Alert.alert('Could not enable iCloud Drive', (e as Error).message);
      }
    };

    if (existingTasks === null) {
      await finalize(true);
      return;
    }

    Alert.alert(
      'Existing todo.txt found',
      `"${name}" already has a todo.txt with ${existingTasks.length} task(s). This device currently has ${tasks.length} task(s).`,
      [
        { text: 'Cancel', style: 'cancel' },
        { text: `Use iCloud's ${existingTasks.length} tasks`, onPress: () => finalize(false) },
        { text: `Keep this device's ${tasks.length} tasks`, style: 'destructive', onPress: () => finalize(true) },
      ]
    );
  }

  function handleSwitchToLocal() {
    Alert.alert(
      'Switch to local storage?',
      'This copies your current tasks to local storage on this device only. Continue?',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Switch to Local',
          style: 'destructive',
          onPress: async () => {
            try {
              await disableICloud();
            } catch (e) {
              Alert.alert('Could not switch to local storage', (e as Error).message);
            }
          },
        },
      ]
    );
  }

  return (
    <ScrollView style={[styles.screen, { paddingTop: insets.top }]} contentContainerStyle={{ paddingBottom: 120 }}>
      <Text style={styles.sectionTitle}>Storage Location</Text>
      <View style={styles.card}>
        <View style={styles.option}>
          <Text style={styles.optionLabel}>{storageInfo.mode === 'icloud' ? 'ICLOUD DRIVE' : 'LOCAL'}</Text>
          <Text style={styles.optionDesc}>
            {storageInfo.mode === 'icloud' ? storageInfo.label : 'This device only.'}
          </Text>
        </View>
        <View style={styles.divider} />
        {storageInfo.mode === 'local' ? (
          <TouchableOpacity style={styles.option} onPress={handleUseICloud} activeOpacity={0.7}>
            <Text style={[styles.optionLabel, styles.optionLabelActive]}>USE ICLOUD DRIVE</Text>
            <Text style={styles.optionDesc}>Choose or create a folder in iCloud Drive — we suggest naming it &quot;Stark&quot;.</Text>
          </TouchableOpacity>
        ) : (
          <TouchableOpacity style={styles.option} onPress={handleSwitchToLocal} activeOpacity={0.7}>
            <Text style={[styles.optionLabel, styles.optionLabelDestructive]}>SWITCH TO LOCAL</Text>
            <Text style={styles.optionDesc}>Copy tasks back to this device only.</Text>
          </TouchableOpacity>
        )}
      </View>

      <Text style={styles.sectionTitle}>Transfer</Text>
      <View style={styles.card}>
        <TouchableOpacity style={styles.option} onPress={handleExport} activeOpacity={0.7}>
          <Text style={styles.optionLabel}>EXPORT</Text>
          <Text style={styles.optionDesc}>Share this device's tasks as a todo.txt file.</Text>
        </TouchableOpacity>
        <View style={styles.divider} />
        <TouchableOpacity style={styles.option} onPress={handleImport} activeOpacity={0.7}>
          <Text style={styles.optionLabel}>IMPORT</Text>
          <Text style={styles.optionDesc}>Pick a todo.txt file to replace everything on this device.</Text>
        </TouchableOpacity>
      </View>

      <Text style={styles.sectionTitle}>Week starts on</Text>
      <View style={styles.card}>
        <TouchableOpacity
          style={[styles.option, weekStart === 0 && styles.optionActive]}
          onPress={() => setWeekStart(0)}
          activeOpacity={0.7}
        >
          <Text style={[styles.optionLabel, weekStart === 0 && styles.optionLabelActive]}>SUNDAY</Text>
        </TouchableOpacity>
        <View style={styles.divider} />
        <TouchableOpacity
          style={[styles.option, weekStart === 1 && styles.optionActive]}
          onPress={() => setWeekStart(1)}
          activeOpacity={0.7}
        >
          <Text style={[styles.optionLabel, weekStart === 1 && styles.optionLabelActive]}>MONDAY</Text>
        </TouchableOpacity>
      </View>

      <Text style={styles.sectionTitle}>Current path</Text>
      <View style={styles.card}>
        <Text style={styles.currentPath}>{storageInfo.label}</Text>
      </View>

      <Text style={styles.sectionTitle}>About</Text>
      <View style={styles.card}>
        <View style={styles.aboutRow}>
          <Text style={styles.aboutLabel}>APP NAME</Text>
          <Text style={styles.aboutValue}>{appName}</Text>
        </View>
        <View style={styles.divider} />
        <View style={styles.aboutRow}>
          <Text style={styles.aboutLabel}>VERSION</Text>
          <Text style={styles.aboutValue}>{appVersion}{buildNumber ? ` (${buildNumber})` : ''}</Text>
        </View>
        <View style={styles.divider} />
        <TouchableOpacity
          style={styles.aboutRow}
          onPress={() => Linking.openURL('http://caritos.com')}
          activeOpacity={0.7}
        >
          <Text style={styles.aboutLabel}>DEVELOPER</Text>
          <Text style={styles.aboutLink}>Eladio Caritos</Text>
        </TouchableOpacity>
        <View style={styles.divider} />
        <TouchableOpacity
          style={styles.option}
          onPress={() => Linking.openURL('https://stark.caritos.com/privacy')}
          activeOpacity={0.7}
        >
          <Text style={[styles.optionLabel, styles.optionLabelActive]}>PRIVACY POLICY</Text>
        </TouchableOpacity>
      </View>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: Colors.background },
  sectionTitle: {
    fontSize: 11,
    color: Colors.textSecondary,
    textTransform: 'uppercase',
    letterSpacing: 2,
    fontWeight: '600',
    paddingHorizontal: Spacing.md,
    paddingTop: Spacing.lg,
    paddingBottom: Spacing.sm,
  },
  card: {
    backgroundColor: Colors.surface,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderColor: Colors.separator,
  },
  option: {
    paddingHorizontal: Spacing.md,
    paddingVertical: Spacing.md,
    gap: 4,
  },
  optionActive: {},
  optionLabel: {
    fontSize: 13,
    letterSpacing: 2,
    color: Colors.textSecondary,
    fontFamily: Fonts.mono,
  },
  optionLabelActive: { color: Colors.accent },
  optionLabelDestructive: { color: Colors.actionDelete },
  optionDesc: { fontSize: 12, color: Colors.textSecondary, lineHeight: 17 },
  divider: {
    height: StyleSheet.hairlineWidth,
    backgroundColor: Colors.separator,
    marginLeft: Spacing.md,
  },
  currentPath: { fontFamily: Fonts.mono, fontSize: 11, color: Colors.textSecondary, lineHeight: 18, padding: Spacing.md },
  aboutRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: Spacing.md,
    paddingVertical: Spacing.md,
  },
  aboutLabel: { fontSize: 13, letterSpacing: 2, color: Colors.textSecondary, fontFamily: Fonts.mono },
  aboutValue: { fontSize: 13, color: Colors.text, fontFamily: Fonts.mono },
  aboutLink: { fontSize: 13, color: Colors.accent, fontFamily: Fonts.mono },
});
