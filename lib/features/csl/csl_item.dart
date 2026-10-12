import '../../data/database.dart';
import '../library/authors.dart';

const _particles = {
  'van',
  'von',
  'de',
  'der',
  'den',
  'del',
  'della',
  'di',
  'da',
  'dos',
  'du',
  'la',
  'le',
  'ten',
  'ter',
  'bin',
  'ibn',
  'al',
  'el',
};

final _conferenceWords = RegExp(
  r'\b(proc|proceedings|conference|conf|symposium|workshop|congress|'
  r'neurips|nips|icml|iclr|cvpr|iccv|eccv|acl|emnlp|naacl|aaai|ijcai|kdd|'
  r'sigir|sigmod|sigcomm|chi|uist|icra|iros|interspeech|icassp|www)\b',
  caseSensitive: false,
);

/// Where a venue string says "preprint server".
bool isPreprintServer(String? venue, String? doi) {
  final v = (venue ?? '').toLowerCase();
  final d = (doi ?? '').toLowerCase();
  return d.startsWith('10.48550/arxiv.') ||
      v.contains('arxiv') ||
      v.contains('biorxiv') ||
      v.contains('medrxiv') ||
      v.contains('ssrn') ||
      v.contains('preprint');
}

/// The arXiv id, from the DOI (`10.48550/arXiv.1706.03762`) or the venue
/// ("arXiv:1706.03762").
String? arxivId(String? venue, String? doi) {
  final d = RegExp(
    r'^10\.48550/arxiv\.(.+)$',
    caseSensitive: false,
  ).firstMatch((doi ?? '').trim());
  if (d != null) return d.group(1);
  final v = RegExp(
    r'arxiv[:\s]*([0-9]{4}\.[0-9]{4,5}(v\d+)?|[a-z\-]+(\.[A-Z]{2})?/\d{7})',
    caseSensitive: false,
  ).firstMatch(venue ?? '');
  return v?.group(1);
}

/// Splits "van der Berg" into the particle and the family name proper.
(String particle, String family) splitParticle(String family) {
  final tokens = family.split(RegExp(r'\s+'));
  var i = 0;
  while (i < tokens.length - 1 && _particles.contains(tokens[i])) {
    i++;
  }
  // Only lowercase particles count ("Van Gogh" keeps its capital).
  if (i == 0) return ('', family);
  return (tokens.sublist(0, i).join(' '), tokens.sublist(i).join(' '));
}

/// The CSL type Corplex assumes for [paper], from its venue and DOI.
String cslTypeOf(Paper paper) {
  final venue = paper.venue?.trim() ?? '';
  if (isPreprintServer(venue, paper.doi)) return 'article';
  if (venue.isNotEmpty && _conferenceWords.hasMatch(venue)) {
    return 'paper-conference';
  }
  if (venue.isNotEmpty || (paper.doi ?? '').isNotEmpty) {
    return 'article-journal';
  }
  return 'article';
}

/// A paper as CSL-JSON (https://citeproc-js.readthedocs.io/en/latest/csl-json).
Map<String, dynamic> paperToCsl(Paper paper) {
  final type = cslTypeOf(paper);
  final list = parseAuthors(paper.authors);
  final venue = paper.venue?.trim() ?? '';
  final doi = (paper.doi ?? '').trim();
  final preprint = isPreprintServer(venue, doi);
  final item = <String, dynamic>{
    'id': (paper.citekey ?? '').isNotEmpty ? paper.citekey : paper.id,
    'type': type,
    'title': paper.title.trim(),
  };
  if (list.authors.isNotEmpty) {
    item['author'] = [
      for (final a in list.authors)
        if (a.given.isEmpty &&
            a.family.contains(' ') &&
            splitParticle(a.family).$1.isEmpty)
          // One word group with no given name: a group author.
          {'literal': a.family}
        else
          () {
            final (particle, family) = splitParticle(a.family);
            return {
              'family': family,
              if (a.given.isNotEmpty) 'given': a.given,
              if (particle.isNotEmpty) 'non-dropping-particle': particle,
            };
          }(),
    ];
    if (list.etAl) item['_etAl:author'] = true;
  }
  if (paper.year != null) {
    item['issued'] = {
      'date-parts': [
        [paper.year],
      ],
    };
  }
  if (doi.isNotEmpty) item['DOI'] = doi;
  if (preprint) {
    final id = arxivId(venue, doi);
    final server = venue.toLowerCase().contains('arxiv') || id != null
        ? 'arXiv'
        : venue;
    item['publisher'] = server;
    if (id != null) {
      item['number'] = 'arXiv:$id';
      if (doi.isEmpty || doi.toLowerCase().startsWith('10.48550/')) {
        item['URL'] = 'https://arxiv.org/abs/$id';
      }
    }
  } else if (venue.isNotEmpty) {
    item['container-title'] = venue;
  }
  return item;
}
