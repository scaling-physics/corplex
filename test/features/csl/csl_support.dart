import 'dart:io';

import 'package:corplex/features/csl/csl_locale.dart';
import 'package:corplex/features/csl/csl_processor.dart';
import 'package:corplex/features/csl/csl_style.dart';

CslLocale testLocale() =>
    CslLocale.parse(File('assets/csl/locales-en-US.xml').readAsStringSync())
        .withoutTerms({'advance-online-publication'});

CslProcessor processorFor(String file) => CslProcessor(
  CslStyle.parse(File('assets/csl/$file.csl').readAsStringSync(), testLocale()),
);

Map<String, dynamic> person(String family, String given) => {
  'family': family,
  'given': given,
};

final vaswani = <String, dynamic>{
  'id': 'vaswani2017',
  'type': 'paper-conference',
  'title': 'Attention is all you need',
  'author': [
    person('Vaswani', 'Ashish'),
    person('Shazeer', 'Noam'),
    person('Parmar', 'Niki'),
  ],
  'issued': {
    'date-parts': [
      [2017],
    ],
  },
  'container-title': 'Advances in Neural Information Processing Systems',
};

final journal = <String, dynamic>{
  'id': 'smith2020',
  'type': 'article-journal',
  'title': 'deep learning for cats',
  'author': [person('Smith', 'John Paul'), person('Jones', 'Kim')],
  'issued': {
    'date-parts': [
      [2020],
    ],
  },
  'container-title': 'Journal of Feline Science',
  'DOI': '10.1000/xyz123',
};

Map<String, dynamic> paper(
  String id,
  String type,
  String title,
  List<Map<String, dynamic>> authors, {
  int? year,
  String? venue,
  String? doi,
  Map<String, dynamic> extra = const {},
}) => {
  'id': id,
  'type': type,
  'title': title,
  if (authors.isNotEmpty) 'author': authors,
  if (year != null)
    'issued': {
      'date-parts': [
        [year],
      ],
    },
  'container-title': ?venue,
  'DOI': ?doi,
  ...extra,
};

final eight = paper(
  'eight',
  'article-journal',
  'Many hands make light work',
  [
    person('Alpha', 'Anna'),
    person('Beta', 'Bob'),
    person('Gamma', 'Carl'),
    person('Delta', 'Dina'),
    person('Epsilon', 'Eve'),
    person('Zeta', 'Finn'),
    person('Eta', 'Gus'),
    person('Theta', 'Hana'),
  ],
  year: 2019,
  venue: 'Journal of Teamwork',
  doi: '10.1/many',
);

final berg = paper(
  'berg',
  'article-journal',
  'Dutch dykes revisited',
  [
    {'family': 'Berg', 'given': 'Anna', 'non-dropping-particle': 'van der'},
  ],
  year: 2018,
  venue: 'Water Science',
);

final nodate = paper('nodate', 'article-journal', 'Timeless results', [
  person('Doe', 'Jane'),
], venue: 'Journal of Eternity');

final arxiv = paper(
  'arxiv',
  'article',
  'Scaling laws for neural language models',
  [person('Kaplan', 'Jared'), person('McCandlish', 'Sam')],
  year: 2020,
  extra: {
    'publisher': 'arXiv',
    'genre': 'Preprint',
    'number': 'arXiv:2001.08361',
    'URL': 'https://arxiv.org/abs/2001.08361',
  },
);
