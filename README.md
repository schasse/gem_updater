# gem_updater
gem_updater creates automatic pull-requests with gem updates.

``` shell
docker run --rm \
  --env='GITHUB_TOKEN=asdfasdfasdfasdf' \
  --env="REPOSITORIES='rails/rails rails/actioncable'" \
  schasse/gem_updater
```
