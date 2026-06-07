use skim::fuzzy_matcher::FuzzyMatcher;
use skim::prelude::SkimMatcherV2;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RankedMatch<T> {
    pub score: i64,
    pub item: T,
}

pub fn fuzzy_score(candidate: &str, query: &str) -> Option<i64> {
    SkimMatcherV2::default()
        .ignore_case()
        .fuzzy_match(candidate, query)
}

pub fn rank_fuzzy<T>(
    query: &str,
    candidates: impl IntoIterator<Item = T>,
    key: impl Fn(&T) -> &str,
) -> Vec<RankedMatch<T>> {
    let query = query.trim();
    let mut ranked = if query.is_empty() {
        candidates
            .into_iter()
            .map(|item| RankedMatch {
                score: i64::MAX,
                item,
            })
            .collect::<Vec<_>>()
    } else {
        candidates
            .into_iter()
            .filter_map(|item| {
                fuzzy_score(key(&item), query).map(|score| RankedMatch { score, item })
            })
            .collect::<Vec<_>>()
    };
    ranked.sort_by(|left, right| {
        right
            .score
            .cmp(&left.score)
            .then_with(|| key(&left.item).cmp(key(&right.item)))
    });
    ranked
}

pub fn rank_fuzzy_by<T>(
    query: &str,
    candidates: impl IntoIterator<Item = T>,
    score: impl Fn(&T, &str) -> Option<i64>,
    tie_breaker: impl Fn(&T) -> &str,
) -> Vec<RankedMatch<T>> {
    let query = query.trim();
    let mut ranked = candidates
        .into_iter()
        .filter_map(|item| score(&item, query).map(|score| RankedMatch { score, item }))
        .collect::<Vec<_>>();
    ranked.sort_by(|left, right| {
        right
            .score
            .cmp(&left.score)
            .then_with(|| tie_breaker(&left.item).cmp(tie_breaker(&right.item)))
    });
    ranked
}

pub fn format_ambiguous_query(kind: &str, query: &str, candidates: &[String]) -> String {
    let mut message = format!("ambiguous {kind} query: {query}\nPotential matches:");
    for candidate in candidates {
        message.push_str(&format!("\n  - {candidate}"));
    }
    message
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fuzzy_scores_subsequence_matches() {
        assert!(fuzzy_score("abcdef", "abc").is_some());
        assert!(fuzzy_score("abcdef", "acf").is_some());
        assert_eq!(fuzzy_score("abcdef", "az"), None);
    }

    #[test]
    fn ranks_empty_queries_by_key() {
        let ranked = rank_fuzzy("", ["beta", "alpha"], |candidate| candidate).into_iter();
        assert_eq!(
            ranked.map(|ranked| ranked.item).collect::<Vec<_>>(),
            vec!["alpha", "beta"]
        );
    }

    #[test]
    fn ranks_non_empty_queries_by_score_then_key() {
        let ranked = rank_fuzzy("ab", ["axby", "abz", "zab"], |candidate| candidate).into_iter();
        assert_eq!(
            ranked.map(|ranked| ranked.item).collect::<Vec<_>>(),
            vec!["abz", "axby", "zab"]
        );
    }

    #[test]
    fn formats_ambiguous_errors() {
        assert_eq!(
            format_ambiguous_query("project", "foo", &["a".to_string(), "b".to_string()]),
            "ambiguous project query: foo\nPotential matches:\n  - a\n  - b"
        );
    }
}
