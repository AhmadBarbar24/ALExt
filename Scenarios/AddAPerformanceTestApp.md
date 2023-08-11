# #16 Add a performance test app to an existing project
*Prerequisites: A completed [scenario 1](GetStarted.md)*

1. On **github.com**, open **Actions** on your solution, select **Create a new performance test app** and then choose **Run workflow**. Enter values for **name**, **publisher**, and **ID range** and choose **Run workflow**
![Run Workflow](https://github.com/microsoft/AL-Go/assets/10775043/40f9bda7-578b-4844-9c2b-f59200d04584)
1. When the workflow is done, navigate to **Pull Requests**, **inspect the PR** and **Merge the pull request**
![Pull Request](images/16b.png)
1. Under **Actions**, you will see that a Merge pull request **CI workflow** has been kicked off
![Workflows](images/16c.png)
1. If you wait for the workflow to complete, you will see that it completes and one of the build artifacts are the **BCPT Test Results**
![Fail](images/16d.png)
1. Opening the **BCPT Test Results** and inspecting the results looks like this
![Test failure](images/16e.png)
1. Currently there isn't a visual viewer of these results. The goal is to have a PowerBI dashboard, which can gather BCPT test results from multiple builds and compare.

---
[back](../README.md)
