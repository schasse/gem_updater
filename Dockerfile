FROM ruby:2.3.1

ENV BUNDLE_PATH=vendor/bundle
COPY update_gems.rb /usr/bin/update_gems.rb

RUN wget -O- https://github.com/github/hub/releases/download/v2.2.3/hub-linux-amd64-2.2.3.tgz | tar zx
RUN cp hub-linux-amd64-2.2.3/bin/hub /usr/bin/

ENV GEM_HOME /usr/local/lib/ruby/gems/2.3.0
RUN gem uninstall bundler
ENV BUNDLER_VERSION 1.12.5
RUN gem install bundler --version $BUNDLER_VERSION
ENV GEM_HOME /usr/local/bundle

RUN mkdir -p /mnt
WORKDIR /mnt

CMD /usr/bin/update_gems.rb
