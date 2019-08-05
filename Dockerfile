FROM ruby:2.5.1

RUN wget -O- https://github.com/github/hub/releases/download/v2.2.3/hub-linux-amd64-2.2.3.tgz | tar zx
RUN cp hub-linux-amd64-2.2.3/bin/hub /usr/bin/

ENV GEM_HOME /usr/local/lib/ruby/gems/2.5.0
RUN gem uninstall bundler
ENV BUNDLER_VERSION 1.16.2
RUN gem install bundler --version $BUNDLER_VERSION
RUN gem install rspec --version 3.8.0
RUN gem install pry
ENV GEM_HOME /usr/local/bundle

COPY . /usr/lib/gem_updater
RUN ln -s /usr/lib/gem_updater/update_gems.rb /usr/bin/update_gems.rb

RUN mkdir -p /mnt
WORKDIR /mnt

CMD /usr/bin/update_gems.rb
