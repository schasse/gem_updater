<p align="center">
<img src="logo/gem_updater.png" alt="GemUpdater" title="GemUpdater" />
</p>

[![Build Status](https://travis-ci.org/schasse/gem_updater.svg?branch=master)](https://travis-ci.org/schasse/gem_updater)

# GemUpdater

GemUpdater automatically creates pull-requests with gem updates. Just
run the following.

``` shell
docker run --rm \
  --env='GITHUB_TOKEN=asdfasdfasdfasdf' \
  --env="REPOSITORIES='rails/rails rails/actioncable'" \
  schasse/gem_updater
```

And a pull request per gem will be
created. See
[schasse/outdated#3](https://github.com/schasse/outdated/pull/3) as
example pull request.

![](https://github.com/schasse/gem_updater/blob/master/logo/example_pull_request.png)


## Development

Running the tests:

``` shell
docker build --tag schasse/gem_updater .
docker run schasse/gem_updater bash -c 'rspec'
```
