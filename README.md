<p align="center">
<img src="logo/gem_updater.png" alt="GemUpdater" title="GemUpdater" />
</p>

[[Build Status](https://travis-ci.org/schasse/gem_updater.svg?branch=master)](https://travis-ci.org/schasse/gem_updater)!

# GemUpdater

GemUpdater automatically creates pull-requests with gem updates.

``` shell
docker run --rm \
  --env='GITHUB_TOKEN=asdfasdfasdfasdf' \
  --env="REPOSITORIES='rails/rails rails/actioncable'" \
  schasse/gem_updater
```
