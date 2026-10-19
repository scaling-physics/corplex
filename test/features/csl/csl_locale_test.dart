import 'dart:io';

import 'package:corplex/features/csl/citation_language.dart';
import 'package:corplex/features/csl/csl_locale.dart';
import 'package:corplex/features/csl/csl_processor.dart';
import 'package:corplex/features/csl/csl_registry.dart';
import 'package:corplex/features/csl/csl_style.dart';
import 'package:flutter_test/flutter_test.dart';

import 'csl_support.dart';

/// A tiny style that exercises what a locale decides: quotes, a text date,
/// an ordinal, "et al." and "and".
String _mini({String defaultLocale = '', String locales = ''}) =>
    '''
<style xmlns="http://purl.org/net/xbiblio/csl" version="1.0" class="in-text" $defaultLocale>
  <info><title>Mini</title><id>mini</id></info>
  $locales
  <citation>
    <layout delimiter="; " prefix="(" suffix=")">
      <names variable="author">
        <name form="short" and="text" et-al-min="3" et-al-use-first="1"/>
      </names>
    </layout>
  </citation>
  <bibliography>
    <layout>
      <names variable="author" suffix=".">
        <name and="text" initialize-with=". "/>
      </names>
      <text variable="title" quotes="true" prefix=" " suffix=","/>
      <date variable="issued" form="text" prefix=" "/>
      <number variable="edition" form="ordinal" prefix=", "/>
    </layout>
  </bibliography>
</style>
''';

final _item = <String, dynamic>{
  'id': 'm',
  'type': 'book',
  'title': 'Wasser',
  'author': [person('Kim', 'Ann'), person('Lee', 'Bo')],
  'issued': {
    'date-parts': [
      [2019, 3, 5],
    ],
  },
  'edition': '2',
};

final _three = <String, dynamic>{
  ..._item,
  'author': [person('Kim', 'Ann'), person('Lee', 'Bo'), person('Park', 'Cy')],
};

Future<CslProcessor> _mini2(String tag, {String locales = ''}) async {
  CslRegistry.loadAsset = (p) => File(p).readAsString();
  return CslProcessor(
    CslStyle.parse(_mini(locales: locales), await CslRegistry.localeFor(tag)),
  );
}

void main() {
  setUp(() {
    CslRegistry.loadAsset = (p) => File(p).readAsString();
    CslRegistry.debugReset();
  });

  group('German output', () {
    test('Harvard in de-DE: u. a., quotes, month names, ordinals', () async {
      final p = await _mini2('de-DE');
      final out = p.process(
        [_three, _item],
        clusters: [
          [0],
          [1],
        ],
      );
      expect(out.citations.map((e) => e.plain), [
        '(Kim u.\u00A0a.)',
        '(Kim und Lee)',
      ]);
      expect(
        out.bibliography.last.plain,
        'A. Kim und B. Lee. „Wasser“, 5. März 2019, 2.',
        reason: 'German quotes, and the comma stays outside them',
      );
    });

    test('the same item in en-US is English', () async {
      final p = await _mini2('en-US');
      final out = p.process(
        [_three, _item],
        clusters: [
          [0],
          [1],
        ],
      );
      expect(out.citations.map((e) => e.plain), [
        '(Kim et al.)',
        '(Kim and Lee)',
      ]);
      expect(
        out.bibliography.last.plain,
        'A. Kim and B. Lee. “Wasser,” March 5, 2019, 2nd',
      );
    });

    test('APA in de-DE keeps the style\'s own German "et al."', () async {
      final p = await processorForLocale('apa', 'de-DE');
      final out = p.process(
        [eight],
        clusters: [
          [0],
        ],
      );
      // apa.csl has <locale xml:lang="de"> with et-al = "et al.".
      expect(out.citations.single.plain, '(Alpha et al., 2019)');
      expect(out.bibliography.single.plain, contains('& Theta'));
    });

    test('French: other quotes and terms', () async {
      final p = await _mini2('fr-FR');
      final out = p.process([_item]);
      expect(out.bibliography.single.plain, contains('5 mars 2019'));
      expect(out.bibliography.single.plain, contains('«\u00A0Wasser\u00A0»'));
    });

    test('a gendered ordinal follows the term\'s gender', () async {
      final fr = await CslRegistry.localeFor('fr-FR');
      expect(fr.genderOf('edition'), 'feminine');
      expect(fr.ordinalSuffix(1, gender: 'feminine'), 'ʳᵉ');
      expect(fr.ordinalSuffix(1, gender: 'masculine'), 'ᵉʳ');
      expect(fr.ordinalSuffix(2), 'ᵉ');
    });

    test('English ordinals: st nd rd th, and 11-13 are th', () async {
      final en = await CslRegistry.localeFor('en-US');
      String s(int n) => '$n${en.ordinalSuffix(n)}';
      expect([1, 2, 3, 4, 11, 12, 13, 21, 22, 101, 111, 112].map(s), [
        '1st',
        '2nd',
        '3rd',
        '4th',
        '11th',
        '12th',
        '13th',
        '21st',
        '22nd',
        '101st',
        '111th',
        '112th',
      ]);
    });

    test(
      'German ordinals are a full stop; no English suffix survives',
      () async {
        final de = await CslRegistry.localeFor('de-DE');
        expect([1, 2, 3, 21].map(de.ordinalSuffix), ['.', '.', '.', '.']);
      },
    );
  });

  group('fallback chain', () {
    test('de-AT -> de-DE -> en-US', () {
      expect(CitationLocales.fileChain('de-AT'), ['en-US', 'de-DE', 'de-AT']);
      expect(CitationLocales.fileChain('de-DE'), ['en-US', 'de-DE']);
      expect(CitationLocales.fileChain('fr-CA'), ['en-US', 'fr-FR']);
      expect(CitationLocales.fileChain('xx-YY'), ['en-US']);
      expect(CitationLocales.fileChain('en-GB'), ['en-US', 'en-GB']);
    });

    test(
      'de-AT reads its own file, de-DE the rest, en-US the remainder',
      () async {
        final at = await CslRegistry.localeFor('de-AT');
        final de = await CslRegistry.localeFor('de-DE');
        expect(at.tag, 'de-AT');
        expect(at.term('et-al'), 'u.\u00A0a.');
        // Austrian months differ from German ones.
        expect(at.term('month-01'), 'Jänner');
        expect(de.term('month-01'), 'Januar');
        // Inherited from en-US where no German file says anything.
        expect(at.term('and', form: 'symbol'), '&');
      },
    );

    test('an unknown language is plain English', () async {
      final l = await CslRegistry.localeFor('xx-YY');
      expect(l.term('and'), 'and');
      expect(l.openQuote, '“');
    });

    test('an unbundled dialect uses its language\'s primary file', () async {
      final l = await CslRegistry.localeFor('fr-CA');
      expect(l.tag, 'fr-CA');
      expect(l.term('and'), 'et');
    });

    test('a locale is read once per tag', () async {
      expect(
        await CslRegistry.localeFor('de-DE'),
        same(await CslRegistry.localeFor('de-DE')),
      );
    });
  });

  group('a style\'s own <locale> blocks', () {
    const blocks = '''
<locale><terms><term name="and">plus</term></terms></locale>
<locale xml:lang="en"><terms><term name="et-al">and others</term></terms></locale>
<locale xml:lang="en-GB"><terms><term name="et-al">and co.</term></terms></locale>
<locale xml:lang="de"><terms><term name="et-al">und andere</term></terms></locale>
''';

    test('only blocks for the chosen language apply', () async {
      Future<List<String>> cites(String tag) async {
        final p = await _mini2(tag, locales: blocks);
        return p
            .process(
              [_three, _item],
              clusters: [
                [0],
                [1],
              ],
            )
            .citations
            .map((e) => e.plain)
            .toList();
      }

      expect(await cites('en-US'), ['(Kim and others)', '(Kim plus Lee)']);
      expect(await cites('en-GB'), ['(Kim and co.)', '(Kim plus Lee)']);
      expect(await cites('de-AT'), ['(Kim und andere)', '(Kim plus Lee)']);
      // French: neither the en nor the de block; only the all-language one.
      expect(await cites('fr-FR'), ['(Kim et al.)', '(Kim plus Lee)']);
    });
  });

  group('Automatic', () {
    test('explicit choice, style default, app language, then en-US', () {
      String r({String? c, String? s, String? a}) =>
          CitationLocales.resolve(choice: c, styleDefault: s, appLanguage: a);
      expect(r(), 'en-US');
      expect(r(a: 'de'), 'de-DE');
      expect(r(a: 'de_AT'), 'de-AT');
      expect(r(a: 'en-GB'), 'en-GB');
      expect(r(a: 'pt'), 'pt-BR');
      expect(r(a: 'ja'), 'en-US');
      expect(
        r(s: 'en-GB', a: 'de'),
        'en-GB',
        reason: 'the style speaks first',
      );
      expect(
        r(c: 'fr-FR', s: 'en-GB', a: 'de'),
        'fr-FR',
        reason: 'a choice wins',
      );
    });

    test('a loaded style follows the choice and the device', () async {
      CslRegistry.readChoice = () async => null;
      CslRegistry.writeChoice = (_) async {};
      CslRegistry.appLanguage = () => 'de';
      final apa = await CslRegistry.ensureBundled('apa', 'apa.csl');
      expect(apa!.locale.tag, 'de-DE');
      // A style with a default-locale keeps it under Automatic.
      final nature = await CslRegistry.ensureBundled('nature', 'nature.csl');
      expect(nature!.locale.tag, 'en-GB');
      CslRegistry.appLanguage = () => 'en-US';
    });

    test('choosing a language reloads loaded styles without a gap', () async {
      String? saved;
      CslRegistry.readChoice = () async => null;
      CslRegistry.writeChoice = (t) async => saved = t;
      CslRegistry.appLanguage = () => 'en-US';
      final before = await CslRegistry.ensureBundled('apa', 'apa.csl');
      expect(before!.locale.tag, 'en-US');
      await CslRegistry.setLanguageChoice('fr-FR');
      expect(saved, 'fr-FR');
      expect(CslRegistry.cached('apa')!.locale.tag, 'fr-FR');
      expect(await CslRegistry.languageChoice(), 'fr-FR');
      await CslRegistry.setLanguageChoice(null);
      expect(saved, isNull);
      expect(CslRegistry.cached('apa')!.locale.tag, 'en-US');
    });

    test('labels', () {
      expect(CitationLocales.labelFor('en-US'), 'English US');
      expect(CitationLocales.labelFor('fr-CA'), 'Français');
      expect(CitationLocales.isBundled('pt-BR'), isTrue);
    });
  });

  test('locale terms are available to callers', () async {
    final de = await CslRegistry.localeFor('de-DE');
    expect(de.term('figure'), 'Abbildung');
    expect(de.term('reference', plural: true), 'Referenzen');
    expect(languageOf('de-AT'), 'de');
  });
}
