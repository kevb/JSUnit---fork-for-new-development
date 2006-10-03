/*
 * Copyright (C) 2006 J�rg Schaible
 * Created on 15.09.2006 by J�rg Schaible
 * 
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package de.berlios.jsunit.ant;

import de.berlios.jsunit.JsUnitException;
import de.berlios.jsunit.JsUnitRhinoRunner;
import de.berlios.jsunit.JsUnitRuntimeException;

import org.apache.tools.ant.BuildException;
import org.apache.tools.ant.Project;
import org.apache.tools.ant.Task;

import java.io.File;
import java.io.FileNotFoundException;
import java.io.FileReader;
import java.io.IOException;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;


/**
 * An Ant task for JsUnit. The task allows the execution of JavaScript unit tests and creates
 * XML reports, that can be processed by the Ant junitreport task. Define the task as follows:
 * 
 * <pre>
 *  &lt;taskdef name=&quot;jsunit&quot; className=&quot;de.berlios.jsunit.ant.JsUnitTask&quot; /&gt;
 *  
 *  &lt;jsunit dir=&quot;sourceDir&quot;&gt;
 *      &lt;source file=&quot;money/IMoney.js&quot; /&gt;
 *      &lt;testsuite name=&quot;MyTestSuite&quot; todir=&quot;build/test-reports&quot; type=&quot;RUN_TESTSUITES&quot;&gt;
 *          &lt;fileset dir=&quot;.&quot;&gt;
 *              &lt;include name=&quot;* /**Test.js&quot; /&gt;
 *          &lt;/fileset&gt;
 *      &lt;/testsuite&gt;
 *  &lt;/jsunit&gt;
 * </pre>
 * 
 * <p>
 * You may declare multiple <code>source</code> tags, the scripts are loaded into the declared
 * order. You may also declare multiple <code>testsuite</code> sections, each one will
 * generate a separate XML report. The type of the test suite can be one of the following values:
 * </p>
 * <dl>
 * <dt>RUN_ALLTESTS</dt>
 * <dd>Looks for a class AllTests dervied from TestSuite and runs its suite.</dd>
 * <dt>RUN_TESTSUITES</dt>
 * <dd>Looks for all classes ending with TestSuite and that are dervied from TestSuite and run their suites (the default).</dd>
 * <dt>RUN_TESTCASES</dt>
 * <dd>Looks for all classes ending with TestCase and that are dervied from TestCase and runs them.</dd>
 * </dl>
 * 
 * @author J&ouml;rg Schaible
 * @since upcoming
 */
public class JsUnitTask extends Task {

    private File dir = new File(".");
    private final List sources = new ArrayList();
    private final List testSuites = new ArrayList();

    public void execute() throws BuildException {
        final Project project = getProject();
        if (!dir.isDirectory()) {
            throw new BuildException("Source directory not found");
        }
        if (testSuites.isEmpty()) {
            throw new BuildException("No test suites defined");
        }
        for (final Iterator iterTest = testSuites.iterator(); iterTest.hasNext();) {
            JsUnitRhinoRunner runner = null;
            try {
                runner = new JsUnitRhinoRunner();
            } catch (final JsUnitRuntimeException e) {
                throw new BuildException("Cannot evaluate JavaScript code of JsUnit", e);
            }
            for (final Iterator iterSource = sources.iterator(); iterSource.hasNext();) {
                final File file = ((SourceFile)iterSource.next()).getFile();
                try {
                    runner.load(new FileReader(file), file.getName());
                    project.log("Loaded " + file.getName(), Project.MSG_DEBUG);
                } catch (final FileNotFoundException e) {
                    throw new BuildException("Cannot find " + file.getName(), e);
                } catch (final JsUnitException e) {
                    throw new BuildException("Cannot evaluate JavaScript code of "
                            + file.getName(), e);
                } catch (final IOException e) {
                    throw new BuildException("Cannot read complete " + file.getName(), e);
                }
            }
            final JsUnitSuite suite = (JsUnitSuite)iterTest.next();
            System.out.println("Run suite " + suite.getName());
            suite.run(project, runner);
        }
    }

    /**
     * Set the source directory.
     * 
     * @param dir the directory.
     * @since upcoming
     */
    public void setDir(final File dir) {
        this.dir = dir;
    }

    /**
     * Creates a new test suite.
     * 
     * @return the test suite
     * @since upcoming
     */
    public JsUnitSuite createTestSuite() {
        final JsUnitSuite suite = new JsUnitSuite();
        testSuites.add(suite);
        return suite;
    }

    /**
     * Creates a new source.
     * 
     * @return the source file reference
     * @since upcoming
     */
    public SourceFile createSource() {
        final SourceFile source = new SourceFile();
        sources.add(source);
        return source;
    }

   final class SourceFile {
        File file;

        void setFile(final String name) {
            file = new File(dir, name);
        }

        File getFile() {
            return file;
        }

    }
}
