import 'package:flutter_test/flutter_test.dart';
import 'package:hydrawav3/features/clients/domain/client_model.dart';

/// Screens show the nickname; the stored name is untouched (requests still
/// send `clientName` / `nickname` as before).
void main() {
  test('[R4-32] nickname is shown when there is one', () {
    const c = Client(id: '1', clientName: 'bssb-597c4', nickname: 'Rajesh');
    expect(c.displayName, 'Rajesh');
    expect(c.fullName, 'bssb-597c4');
    expect(c.clientName, 'bssb-597c4');
  });

  test('no (or blank) nickname shows the name', () {
    expect(const Client(id: '1', clientName: 'bssb-597c4').displayName,
        'bssb-597c4');
    expect(
        const Client(id: '1', clientName: 'Malik Carter', nickname: '  ')
            .displayName,
        'Malik Carter');
  });
}
