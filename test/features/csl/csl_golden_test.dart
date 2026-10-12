import 'package:flutter_test/flutter_test.dart';

import 'csl_support.dart';

/// Expected strings follow each style's published rules (APA 7, Chicago
/// author-date, IEEE, NLM/Vancouver, Nature) for the Corplex fields we have:
/// no volume, issue or pages. `*x*` marks italics.
final _items = {
  'smith2020': journal,
  'vaswani2017': vaswani,
  'eight': eight,
  'berg': berg,
  'nodate': nodate,
  'arxiv': arxiv,
};

void main() {
  const golden = <String, Map<String, (String, String)>>{
    'apa': {
      'smith2020': (
        'Smith, J. P., & Jones, K. (2020). deep learning for cats. *Journal of Feline Science*. https://doi.org/10.1000/xyz123',
        '(Smith & Jones, 2020)',
      ),
      'vaswani2017': (
        'Vaswani, A., Shazeer, N., & Parmar, N. (2017). Attention is all you need. *Advances in Neural Information Processing Systems*.',
        '(Vaswani et al., 2017)',
      ),
      'eight': (
        'Alpha, A., Beta, B., Gamma, C., Delta, D., Epsilon, E., Zeta, F., Eta, G., & Theta, H. (2019). Many hands make light work. *Journal of Teamwork*. https://doi.org/10.1/many',
        '(Alpha et al., 2019)',
      ),
      'berg': (
        'van der Berg, A. (2018). Dutch dykes revisited. *Water Science*.',
        '(van der Berg, 2018)',
      ),
      'nodate': (
        'Doe, J. (n.d.). Timeless results. *Journal of Eternity*.',
        '(Doe, n.d.)',
      ),
      'arxiv': (
        'Kaplan, J., & McCandlish, S. (2020). *Scaling laws for neural language models* (Preprint arXiv:2001.08361). arXiv. https://arxiv.org/abs/2001.08361',
        '(Kaplan & McCandlish, 2020)',
      ),
    },
    'chicago-author-date': {
      'smith2020': (
        'Smith, John Paul, and Kim Jones. 2020. “Deep Learning for Cats.” *Journal of Feline Science*. https://doi.org/10.1000/xyz123.',
        '(Smith and Jones 2020)',
      ),
      'vaswani2017': (
        'Vaswani, Ashish, Noam Shazeer, and Niki Parmar. 2017. “Attention Is All You Need.” *Advances in Neural Information Processing Systems*.',
        '(Vaswani et al. 2017)',
      ),
      'eight': (
        'Alpha, Anna, Bob Beta, Carl Gamma, et al. 2019. “Many Hands Make Light Work.” *Journal of Teamwork*. https://doi.org/10.1/many.',
        '(Alpha et al. 2019)',
      ),
      'berg': (
        'Berg, Anna van der. 2018. “Dutch Dykes Revisited.” *Water Science*.',
        '(van der Berg 2018)',
      ),
      'nodate': (
        'Doe, Jane. n.d. “Timeless Results.” *Journal of Eternity*.',
        '(Doe, n.d.)',
      ),
      'arxiv': (
        'Kaplan, Jared, and Sam McCandlish. 2020. “Scaling Laws for Neural Language Models.” Preprint arXiv:2001.08361. arXiv. https://arxiv.org/abs/2001.08361.',
        '(Kaplan and McCandlish 2020)',
      ),
    },
    'ieee': {
      'smith2020': (
        '[1] J. P. Smith and K. Jones, “deep learning for cats,” *Journal of Feline Science*, 2020, doi: 10.1000/xyz123.',
        '[1]',
      ),
      'vaswani2017': (
        '[1] A. Vaswani, N. Shazeer, and N. Parmar, “Attention is all you need,” in *Advances in Neural Information Processing Systems*, 2017.',
        '[1]',
      ),
      'eight': (
        '[1] A. Alpha *et al.*, “Many hands make light work,” *Journal of Teamwork*, 2019, doi: 10.1/many.',
        '[1]',
      ),
      'berg': (
        '[1] A. van der Berg, “Dutch dykes revisited,” *Water Science*, 2018.',
        '[1]',
      ),
      'nodate': (
        '[1] J. Doe, “Timeless results,” *Journal of Eternity*.',
        '[1]',
      ),
      'arxiv': (
        '[1] J. Kaplan and S. McCandlish, “Scaling laws for neural language models,” 2020, *arXiv*: arXiv:2001.08361. Available: https://arxiv.org/abs/2001.08361',
        '[1]',
      ),
    },
    'nlm-citation-sequence': {
      'smith2020': (
        '1. Smith JP, Jones K. deep learning for cats. Journal of Feline Science. 2020. doi:10.1000/xyz123',
        '(1)',
      ),
      'vaswani2017': (
        '1. Vaswani A, Shazeer N, Parmar N. Attention is all you need. In: Advances in Neural Information Processing Systems. 2017.',
        '(1)',
      ),
      'eight': (
        '1. Alpha A, Beta B, Gamma C, Delta D, Epsilon E, Zeta F, et al. Many hands make light work. Journal of Teamwork. 2019. doi:10.1/many',
        '(1)',
      ),
      'berg': (
        '1. van der Berg A. Dutch dykes revisited. Water Science. 2018.',
        '(1)',
      ),
      'nodate': ('1. Doe J. Timeless results. Journal of Eternity.', '(1)'),
      'arxiv': (
        '1. Kaplan J, McCandlish S. Scaling laws for neural language models [Preprint] [Internet]. arXiv; 2020. Available from: https://arxiv.org/abs/2001.08361',
        '(1)',
      ),
    },
    'nature': {
      'smith2020': (
        '1. Smith, J. P. & Jones, K. deep learning for cats. *Journal of Feline Science* https://doi.org/10.1000/xyz123 (2020) doi:10.1000/xyz123.',
        '¹',
      ),
      'vaswani2017': (
        '1. Vaswani, A., Shazeer, N. & Parmar, N. Attention is all you need. in *Advances in Neural Information Processing Systems* (2017).',
        '¹',
      ),
      'eight': (
        '1. Alpha, A. *et al.* Many hands make light work. *Journal of Teamwork* https://doi.org/10.1/many (2019) doi:10.1/many.',
        '¹',
      ),
      'berg': (
        '1. van der Berg, A. Dutch dykes revisited. *Water Science* (2018).',
        '¹',
      ),
      'nodate': ('1. Doe, J. Timeless results. *Journal of Eternity*.', '¹'),
      'arxiv': (
        '1. Kaplan, J. & McCandlish, S. Scaling laws for neural language models. Preprint at https://arxiv.org/abs/2001.08361 (2020).',
        '¹',
      ),
    },
  };

  for (final style in golden.entries) {
    group(style.key, () {
      for (final c in style.value.entries) {
        test(c.key, () {
          final out = processorFor(style.key).process(
            [_items[c.key]!],
            clusters: [
              [0],
            ],
          );
          expect(out.bibliography.single.toMarkdown(), c.value.$1);
          expect(out.citations.single.plainWithSuperscripts, c.value.$2);
        });
      }
    });
  }
}
