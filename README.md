<p align="center">
<img src="logo/gem_updater.png" alt="GemUpdater" title="GemUpdater" />
</p>

# GemUpdater

GemUpdater automatically creates pull-requests with gem updates.

``` shell
docker run --rm \
  --env='GITHUB_TOKEN=asdfasdfasdfasdf' \
  --env="REPOSITORIES='rails/rails rails/actioncable'" \
  schasse/gem_updater
```
