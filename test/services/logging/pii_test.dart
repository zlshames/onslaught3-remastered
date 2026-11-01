import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/services/logging/pii.dart';

void main() {
  group('mask', () {
    test('keeps the first and last characters and the length', () {
      expect(PiiRedactor.mask('jane.doe'), 'j******e');
      expect(PiiRedactor.mask('abcd'), 'a***');
      expect(PiiRedactor.mask('abc'), 'a**');
      expect(PiiRedactor.mask('ab'), '**');
      expect(PiiRedactor.mask(''), '');
    });

    test('Pii prints masked', () {
      expect('saved ${const Pii('My Secret Base')}', 'saved M************e');
      expect(const Pii(null).toString(), 'n***');
    });
  });

  group('redact', () {
    String r(String s) => PiiRedactor.redact(s);

    test('e-mail addresses keep only their shape and top-level domain', () {
      expect(r('mail jane.doe@example.com now'), 'mail j******e@e*****e.com now');
      expect(r('a@b.io'), '*@*.io');
    });

    test('secrets after a keyword are removed entirely', () {
      expect(r('password=hunter22 ok'), 'password=******** ok');
      expect(r('Authorization: Bearer abc.def.ghi'), 'Authorization: Bearer ********');
      expect(r('token abc123'), 'token ********');
      expect(r('api_key: "sk-12345"'), 'api_key: "********"');
    });

    test('home folders in paths lose the user name', () {
      expect(r('/Users/jane.doe/Library/app.log'), '/Users/j******e/Library/app.log');
      expect(r('/home/jane/.local/x'), '/home/j***/.local/x');
      expect(r(r'C:\Users\Jane Doe\AppData'), contains(r'C:\Users\J******e\AppData'));
    });

    test('install ids in paths are masked', () {
      const path =
          '/var/mobile/Containers/Data/Application/2F1A9C3E-1B2C-4D5E-8F90-ABCDEF123456/Library';
      expect(r(path), isNot(contains('1B2C-4D5E')));
      expect(r(path), startsWith('/var/mobile/Containers/Data/Application/2'));
    });

    test('IP and MAC addresses keep only their first part', () {
      expect(r('from 192.168.1.24:80'), 'from 192.***.*.**:80');
      expect(r('ip fe80::1ff:fe23:4567:890a'), isNot(contains('4567')));
      expect(r('mac 00:1A:2B:3C:4D:5E'), 'mac 00:**:**:**:**:**');
    });

    test('card numbers keep their last four digits; other long numbers stay', () {
      expect(r('card 4111 1111 1111 1111'), 'card **** **** **** 1111');
      expect(r('hash 1234567890123'), 'hash 1234567890123', reason: 'fails the Luhn check');
    });

    test('phone numbers keep their last two digits', () {
      expect(r('call +49 170 1234567'), 'call +** *** *****67');
      expect(r('call (555) 123-4567'), 'call (***) ***-**67');
      expect(r('call 555-123-4567'), 'call ***-***-**67');
    });

    test('URL query values are masked', () {
      expect(r('GET /x?user=jane&id=42'), 'GET /x?user=j***&id=**');
    });

    test('ordinary log text is left alone', () {
      const lines = [
        'game started mode=normal map=m01 difficulty=easy seed=12345',
        'at 2026-10-21T14:03:05.123Z wave 12 took 1500 ms',
        '#0      main (package:onslaught3_remastered/main.dart:12:5)',
        'version 1.0.0+1 on macos',
      ];
      for (final l in lines) {
        expect(r(l), l);
      }
    });
  });

  group('fields', () {
    test('personal keys are masked, secret keys hidden, others redacted', () {
      expect(PiiRedactor.field('mapName', 'Fortress'), 'F******s');
      expect(PiiRedactor.field('email', 'x@y.zz'), 'x****z');
      expect(PiiRedactor.field('authToken', 'abc'), PiiRedactor.secretMask);
      expect(PiiRedactor.field('wave', 12), '12');
      expect(PiiRedactor.field('note', 'mail a@b.de'), 'mail *@*.de');
      expect(PiiRedactor.field('zip', 'x'), 'x', reason: '"zip" is not the word "ip"');
    });
  });
}
