#! /usr/bin/env perl6
# vim: filetype=perl6
#
# Copyright 2016 Michael Heironimus
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

use v6;

use JSON::Pretty;
use YAMLish;

class PackerGen {
    has %!cfg = ();
    has %.output = ();

    # Constructor taking an optional input file, not inherited by child class.
    submethod BUILD(Str :$yaml='') {
        self.load($yaml);
        self.generate();
    }

    # Load a YAML file from stdin or the named file.
    method load(Str $in) {
        %!cfg = load-yaml(($in ne '') ?? slurp($in) !! $*IN.slurp-rest);
    }

    # Write the generated to JSON to stdout or the given filename.
    multi method save(Str $out where { $out eq '' }) {
        say to-json(%!output);
    }

    multi method save(Str $out) {
        # to-json doesn't have a final newline
        spurt($out, to-json(%!output) ~ "\n");
    }

    # If a config_template element exists, load that content (in order) and
    # then overlay the supplied data. Otherwise just return the data.
    multi method expand_entry(%data
            where { %data<config_template>:exists } --> Hash) {
        my %new = %data<config_template>:delete.map({ load-yaml(slurp($^a)) });
        %(%new, %data);
    }

    multi method expand_entry(%data --> Hash) {
        %data;
    }

    # Process templates and put the name in to a key of the resulting hash.
    method build(Pair (:key(:$name), :value(:$data)) --> Hash) {
        %(self.expand_entry($data), 'name' => $name);
    }

    # Process templates and add the global override definition if there
    # is no override in the provisioner.
    method provision(%prov --> Hash) {
        my %new = self.expand_entry(%prov);
        # I should describe the precedence of multiple override definitions.
        if (%!cfg<provisioner_override>:exists && !(%prov<override>:exists)) {
            %new<override> = %!cfg<provisioner_override>;
        }
        %new;
    }

    # Process templates for a sequence or a single postprocessor.
    multi method postproc(@post --> Seq) {
        @post.map({ self.expand_entry(%^a) });
    }

    multi method postproc(%post --> Hash) {
        self.expand_entry(%post);
    }

    method generate(--> Hash) {
        # At least one builder definition is required by packer.
        %!output<builders> = %!cfg<builders>.map({ self.build($^a) });

        %!output<provisioners> = %!cfg<provisioners>.map({self.provision($^a) })
                if (%!cfg<provisioners>:exists);

        %!output<post-processors> = %!cfg<post-processors>.map({
                self.postproc($^a) }) if (%!cfg<post-processors>:exists);

        %!output<description> = %!cfg<description>
                if (%!cfg<description>:exists);

        %!output<variables> = %!cfg<variables> if (%!cfg<variables>:exists);

        %!output;
    }

}

# --in=input.yaml --out=output.json
sub MAIN(Str :$in='', Str :$out='') {
    my $pg = PackerGen.new(yaml => $in);
    $pg.save($out);
}
