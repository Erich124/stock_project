import '../models.dart';
import 'api_client.dart';

class MarketRepo {
  final ApiClient api;
  MarketRepo(this.api);

  Future<List<RedditPost>> reddit(String ticker) async =>
      (await api.getReddit(ticker)).map((e) => RedditPost.fromJson(e)).toList().cast<RedditPost>();

  Future<(List<SentimentPoint>, SentimentSummary)> sentiment(String ticker) async {
    final res = await api.getSentiment(ticker);
    final pts = (res['series'] as List).map((e)=>SentimentPoint.fromJson(e)).toList();
    final sum = SentimentSummary.fromJson(res['summary']);
    return (pts, sum);
  }
}
