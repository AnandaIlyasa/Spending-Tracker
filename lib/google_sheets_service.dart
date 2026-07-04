import 'package:googleapis/sheets/v4.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'models.dart';
import 'package:logging/logging.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class GoogleSheetsService {
  static final Logger _log = Logger('GoogleSheetsService');

  final String _spreadsheetId = dotenv.env['SPREADSHEET_ID'] ?? '';
  final _credentials = {
    "type": dotenv.env['GCP_TYPE'],
    "project_id": dotenv.env['GCP_PROJECT_ID'],
    "private_key_id": dotenv.env['GCP_PRIVATE_KEY_ID'],
    "private_key": dotenv.env['GCP_PRIVATE_KEY']?.replaceAll(r'\n', '\n'),
    "client_email": dotenv.env['GCP_CLIENT_EMAIL'],
    "client_id": dotenv.env['GCP_CLIENT_ID'] ?? "",
  };

  Future<bool> syncSpendingsToSheets(List<SpendingItem> pendingItems) async {
    if (pendingItems.isEmpty) return true;


    int retryCount = 0;
    const int maxRetries = 3;

    while (retryCount < maxRetries) {
      try {
        _log.info('Attempting cloud sync packet. Items count: ${pendingItems.length}');
        final accountCredentials = ServiceAccountCredentials.fromJson(_credentials);
        final scopes = [SheetsApi.spreadsheetsScope];
        
        final client = await clientViaServiceAccount(accountCredentials, scopes);
        final sheetsApi = SheetsApi(client);

        final List<List<Object>> rowsValue = pendingItems.map((item) {
          return [
            item.id,
            "${item.date.year}-${item.date.month.toString().padLeft(2, '0')}-${item.date.day.toString().padLeft(2, '0')}",
            item.category,
            double.tryParse(item.amount) ?? 0.0,
            DateTime.now().toIso8601String(),
          ];
        }).toList();

        final valueRange = ValueRange.fromJson({
          'values': rowsValue,
        });

        await sheetsApi.spreadsheets.values.append(
          valueRange,
          _spreadsheetId,
          'Sheet1!A:E',
          valueInputOption: 'USER_ENTERED',
        );

        client.close();
        _log.info('Cloud sync completed successfully for ${pendingItems.length} transactions.');
        return true;
        
      } catch (e, stackTrace) {
        if (e.toString().contains('429') || e.toString().toLowerCase().contains('quota')) {
          retryCount++;
          _log.warning('Quota limit exceeded (429). Retry attempt $retryCount of $maxRetries in 2 seconds.');
          
          await Future.delayed(const Duration(seconds: 2));
          continue; 
        }

        _log.severe('Google Sheets synchronization failed with unexpected error exception', e, stackTrace);
        return false;
      }
    }

    _log.warning('Sync process aborted: Max connection retries ($maxRetries) reached without success.');
    return false;
  }

  Future<List<SpendingItem>> fetchSpendingsFromSheets() async {
    try {
      final accountCredentials = ServiceAccountCredentials.fromJson(_credentials);
      final scopes = [SheetsApi.spreadsheetsScope];
      final client = await clientViaServiceAccount(accountCredentials, scopes);
      final sheetsApi = SheetsApi(client);

      // Fetch all data from columns A through E
      final response = await sheetsApi.spreadsheets.values.get(_spreadsheetId, 'Sheet1!A:E');
      client.close();

      if (response.values == null || response.values!.isEmpty) return [];

      List<SpendingItem> downloadedItems = [];
      
      for (var row in response.values!) {
        if (row[0] == 'ID' || row.length < 4) continue; 

        downloadedItems.add(
          SpendingItem(
            id: row[0].toString(),
            date: DateTime.parse(row[1].toString()),
            category: row[2].toString(),
            amount: row[3].toString(),
            isSynced: true,
          ),
        );
      }
      
      _log.info('Successfully downloaded ${downloadedItems.length} items from Google Sheets.');
      return downloadedItems;
    } catch (e, stackTrace) {
      _log.severe('Failed to fetch data from Google Sheets', e, stackTrace);
      return [];
    }
  }

  Future<bool> updateSpendingInSheets(SpendingItem item) async {
    try {
      final accountCredentials = ServiceAccountCredentials.fromJson(_credentials);
      final client = await clientViaServiceAccount(accountCredentials, [SheetsApi.spreadsheetsScope]);
      final sheetsApi = SheetsApi(client);

      final response = await sheetsApi.spreadsheets.values.get(_spreadsheetId, 'Sheet1!A:A');
      if (response.values == null) return false;

      int rowIndex = -1;
      for (int i = 0; i < response.values!.length; i++) {
        if (response.values![i].isNotEmpty && response.values![i][0].toString() == item.id) {
          rowIndex = i + 1;
          break;
        }
      }

      if (rowIndex != -1) {
        final List<Object> updatedRow = [
          "${item.date.year}-${item.date.month.toString().padLeft(2, '0')}-${item.date.day.toString().padLeft(2, '0')}",
          item.category,
          double.tryParse(item.amount) ?? 0.0,
          DateTime.now().toIso8601String(),
        ];
        
        final valueRange = ValueRange.fromJson({'values': [updatedRow]});
        await sheetsApi.spreadsheets.values.update(
          valueRange,
          _spreadsheetId,
          'Sheet1!B$rowIndex:E$rowIndex',
          valueInputOption: 'USER_ENTERED',
        );
        _log.info('Successfully updated row $rowIndex in Google Sheets.');
        client.close();
        return true;
      }
      
      client.close();
      return false;
    } catch (e) {
      _log.severe('Failed to update row in Google Sheets', e);
      return false;
    }
  }

  Future<bool> deleteSpendingFromSheets(String itemId) async {
    try {
      final accountCredentials = ServiceAccountCredentials.fromJson(_credentials);
      final client = await clientViaServiceAccount(accountCredentials, [SheetsApi.spreadsheetsScope]);
      final sheetsApi = SheetsApi(client);

      final response = await sheetsApi.spreadsheets.values.get(_spreadsheetId, 'Sheet1!A:A');
      if (response.values == null) return false;

      int rowIndex = -1;
      for (int i = 0; i < response.values!.length; i++) {
        if (response.values![i].isNotEmpty && response.values![i][0].toString() == itemId) {
          rowIndex = i + 1;
          break;
        }
      }

      if (rowIndex != -1) {
        await sheetsApi.spreadsheets.values.clear(
          ClearValuesRequest(),
          _spreadsheetId,
          'Sheet1!A$rowIndex:E$rowIndex',
        );
        _log.info('Successfully cleared row $rowIndex from Google Sheets.');
        client.close();
        return true;
      }

      client.close();
      return false;
    } catch (e) {
      _log.severe('Failed to delete row from Google Sheets', e);
      return false;
    }
  }
}